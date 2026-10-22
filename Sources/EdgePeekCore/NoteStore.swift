import Combine
import Foundation

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [StickyNote] = []

    public let fileURL: URL
    public let seedIfMissing: Bool
    private var saveTask: Task<Void, Never>?
    private var draftIDs = Set<UUID>()
    private var lastKnownData: Data?

    public init(fileURL: URL? = nil, seedIfMissing: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.seedIfMissing = seedIfMissing
        load()
    }

    public var sortedNotes: [StickyNote] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    public func note(with id: UUID) -> StickyNote? {
        notes.first { $0.id == id }
    }

    @discardableResult
    public func addNote(
        content: String = "",
        color: NoteColor? = nil,
        createdAt: Date = Date()
    ) -> StickyNote {
        let chosenColor = color ?? randomPaperColor()
        let note = StickyNote(
            content: content,
            color: chosenColor,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        notes.insert(note, at: 0)
        synchronizeTagColors()
        scheduleSave()
        return note
    }

    public func updateContent(id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[index].content != content else { return }
        notes[index].content = content
        notes[index].updatedAt = Date()
        synchronizeTagColors()
        scheduleSave()
    }

    public func beginDraft(id: UUID) {
        guard note(with: id) != nil else { return }
        draftIDs.insert(id)
    }

    public func finishDraft(id: UUID) {
        guard draftIDs.contains(id) else { return }
        discardIfEmpty(id: id)
        draftIDs.remove(id)
        saveNow()
    }

    /// Colours are a property of the paper, not a preference. New notes pick a
    /// random tone from the quiet palette; a tagged note then adopts the tone
    /// already established by its group.
    private func randomPaperColor() -> NoteColor {
        let used = Set(notes.map(\.color))
        let unused = NoteColor.allCases.filter { !used.contains($0) }
        return (unused.isEmpty ? NoteColor.allCases : unused).randomElement() ?? .cream
    }

    public func setColor(id: UUID, color: NoteColor) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let tagKey = NoteText.primaryTagKey(in: notes[index].content)

        if let tagKey {
            var changed = false
            for noteIndex in notes.indices
            where NoteText.primaryTagKey(in: notes[noteIndex].content) == tagKey {
                if notes[noteIndex].color != color {
                    notes[noteIndex].color = color
                    notes[noteIndex].updatedAt = Date()
                    changed = true
                }
            }
            if changed {
                scheduleSave()
            }
        } else {
            guard notes[index].color != color else { return }
            notes[index].color = color
            notes[index].updatedAt = Date()
            scheduleSave()
        }
    }

    public func togglePin(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    public func setDueDate(id: UUID, dueAt: Date?) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].dueAt = dueAt
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    /// Move a note to another group by rewriting its primary hashtag. `nil`
    /// removes the tag, which is how a card joins the untagged sheets.
    public func setPrimaryTag(id: UUID, tag: String?) {
        guard let note = note(with: id) else { return }
        guard NoteText.primaryTagKey(in: note.content) != tag?.lowercased() else { return }
        updateContent(
            id: id,
            content: NoteText.replacingPrimaryTag(in: note.content, with: tag)
        )
    }

    public var overdueNotes: [StickyNote] {
        notes.filter { $0.isOverdue }
    }

    public var hasOverdueNotes: Bool {
        notes.contains(where: { $0.isOverdue })
    }

    /// Notes are grouped by their first hashtag. This gives every tagged note
    /// one home and one group colour. An untagged note is a group of its own.
    public var noteGroups: [NoteGroup] {
        let sorted = sortedNotes
        var order: [String] = []
        var displays: [String: String] = [:]
        var members: [String: [StickyNote]] = [:]
        var untagged: [StickyNote] = []

        for note in sorted {
            guard let tag = NoteText.primaryTag(in: note.content) else {
                untagged.append(note)
                continue
            }
            let key = tag.lowercased()
            if members[key] == nil {
                order.append(key)
                displays[key] = tag
            }
            members[key, default: []].append(note)
        }

        var groups: [NoteGroup] = order.map { key in
            NoteGroup(tag: displays[key], key: key, notes: members[key] ?? [])
        }
        for note in untagged {
            groups.append(
                NoteGroup(
                    tag: nil,
                    key: "untagged:\(note.id.uuidString)",
                    notes: [note]
                )
            )
        }
        return groups
    }

    public func delete(id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        draftIDs.remove(id)
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Used by the undo toast after an explicit deletion.
    public func restore(_ note: StickyNote) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        notes.append(note)
        synchronizeTagColors()
        scheduleSave()
    }

    public func discardIfEmpty(id: UUID) {
        guard let note = note(with: id), note.isEmpty else { return }
        delete(id: id)
    }

    /// Preserve open drafts when another local client changes the shared file.
    /// Comparing bytes also avoids reloading our own saves after ISO-8601 dates
    /// have lost their subsecond precision.
    public func reloadFromDiskIfChanged() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard data != lastKnownData else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let fresh = try decoder.decode([StickyNote].self, from: data)
            lastKnownData = data
            let drafts = notes.filter { draftIDs.contains($0.id) }
            let merged = drafts + fresh.filter { !draftIDs.contains($0.id) }
            guard merged != notes else { return }
            saveTask?.cancel()
            saveTask = nil
            notes = merged
            synchronizeTagColors()
            if !drafts.isEmpty { scheduleSave() }
        } catch {
            NSLog("EdgePeek: could not reload externally changed notes: \(error.localizedDescription)")
        }
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let persisted = notes.filter { !draftIDs.contains($0.id) || !$0.isEmpty }
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL, options: .atomic)
            lastKnownData = data
        } catch {
            NSLog("EdgePeek: could not save notes: \(error.localizedDescription)")
        }
    }

    nonisolated public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("EdgePeek", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    /// Keep every note in a tagged group on the same paper colour. The first
    /// note in sorted order sets the tone for a group that was created by hand.
    private func synchronizeTagColors() {
        var groupColors: [String: NoteColor] = [:]
        // The oldest note anchors the group's colour. Adding a new note (which
        // can be newer and have a different default colour) must not repaint the
        // whole tag group.
        let ageOrdered = notes.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for note in ageOrdered {
            guard let key = NoteText.primaryTagKey(in: note.content) else { continue }
            if groupColors[key] == nil {
                groupColors[key] = note.color
            }
        }

        for index in notes.indices {
            guard let key = NoteText.primaryTagKey(in: notes[index].content),
                  let color = groupColors[key],
                  notes[index].color != color else { continue }
            notes[index].color = color
        }
    }

    // MARK: - Loading

    private func load() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            notes = seedIfMissing ? Self.welcomeNotes() : []
            synchronizeTagColors()
            saveNow()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([StickyNote].self, from: data)
            lastKnownData = data
            synchronizeTagColors()
        } catch {
            NSLog("EdgePeek: could not read notes: \(error.localizedDescription)")
            preserveBrokenFile()
            notes = []
            saveNow()
        }
    }

    private func preserveBrokenFile() {
        let backup = fileURL
            .deletingPathExtension()
            .appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: fileURL, to: backup)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - First run

    nonisolated public static func welcomeNotes(now: Date = Date()) -> [StickyNote] {
        [
            StickyNote(
                content: "把鼠标停在这条缝上\n便签会像纸片一样浮出来。\n#用法",
                color: .apricot,
                createdAt: now,
                updatedAt: now
            ),
            StickyNote(
                content: "按住便签上的胶带\n拖动整张纸，松手停在新位置。\n「…」里可以删除，删后可撤销。\n拖着细条可以换边。\n#用法",
                color: .apricot,
                createdAt: now.addingTimeInterval(-60),
                updatedAt: now.addingTimeInterval(-60)
            ),
            StickyNote(
                content: "随时记一笔\n按 ⌘ ⇧ Space 新建便签。\n按 ⌃ ⌥ Space 显示或收起全部便签。\n第一行会变成卡片上的标题。\n#快捷键",
                color: .sky,
                createdAt: now.addingTimeInterval(-120),
                updatedAt: now.addingTimeInterval(-120)
            ),
            StickyNote(
                content: "这里可以写任何想法\n用标签把同类便签放在一起。\n同一条竖列里的纸片，是一伙的。\n#灵感",
                color: .cream,
                createdAt: now.addingTimeInterval(-180),
                updatedAt: now.addingTimeInterval(-180)
            )
        ]
    }
}
