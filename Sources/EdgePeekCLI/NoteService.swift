import Darwin
import EdgePeekCore
import Foundation

struct DueUpdate {
    var isSet: Bool
    var value: Date?

    static let unchanged = DueUpdate(isSet: false, value: nil)

    init(isSet: Bool, value: Date?) {
        self.isSet = isSet
        self.value = value
    }
}

/// The CLI is a second, headless client of the same JSON file the app
/// uses. Reads and writes are deliberately plain and atomic so the running app
/// can pick them up with its file watcher.
struct NoteService {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        if let path = ProcessInfo.processInfo.environment["EDGEPEEK_DATA_FILE"],
           !path.isEmpty {
            self.fileURL = URL(fileURLWithPath: path)
        } else {
            self.fileURL = NoteStore.defaultFileURL()
        }
    }

    func load() throws -> [StickyNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([StickyNote].self, from: data)
    }

    private func save(_ notes: [StickyNote]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notes)
        try data.write(to: fileURL, options: .atomic)
    }

    func sorted(_ notes: [StickyNote]) -> [StickyNote] {
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

    func allNotes() throws -> [StickyNote] {
        sorted(try load())
    }

    func note(id: UUID) throws -> StickyNote? {
        try load().first { $0.id == id }
    }

    func groups() throws -> [NoteGroup] {
        let notes = sorted(try load())
        var order: [String] = []
        var displays: [String: String] = [:]
        var members: [String: [StickyNote]] = [:]
        var untagged: [StickyNote] = []

        for note in notes {
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

        var result: [NoteGroup] = order.map { key in
            NoteGroup(tag: displays[key], key: key, notes: members[key] ?? [])
        }
        for note in untagged {
            result.append(
                NoteGroup(
                    tag: nil,
                    key: "untagged:\(note.id.uuidString)",
                    notes: [note]
                )
            )
        }
        return result
    }

    func search(_ query: String) throws -> [StickyNote] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try allNotes() }
        return try allNotes().filter { note in
            note.content.localizedCaseInsensitiveContains(needle)
                || note.displayTitle.localizedCaseInsensitiveContains(needle)
                || NoteText.tags(in: note.content).contains {
                    $0.localizedCaseInsensitiveContains(needle)
                }
        }
    }

    @discardableResult
    func create(
        content: String,
        dueAt: Date? = nil,
        pinned: Bool = false
    ) throws -> StickyNote {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidArguments("`content` must contain non-whitespace text.")
        }
        return try mutate { notes in
            let now = Date()
            let note = StickyNote(
                content: content,
                color: chooseColor(for: content, in: notes),
                isPinned: pinned,
                createdAt: now,
                updatedAt: now,
                dueAt: dueAt
            )
            notes.insert(note, at: 0)
            synchronizeTagColors(&notes)
            return notes.first { $0.id == note.id } ?? note
        }
    }

    @discardableResult
    func update(
        id: UUID,
        content: String? = nil,
        pinned: Bool? = nil,
        due: DueUpdate = .unchanged
    ) throws -> StickyNote {
        return try mutate { notes in
            guard let index = notes.firstIndex(where: { $0.id == id }) else {
                throw ServiceError.noteNotFound
            }

            if let content {
                notes[index].content = content
            }
            if let pinned {
                notes[index].isPinned = pinned
            }
            if due.isSet {
                notes[index].dueAt = due.value
            }
            notes[index].updatedAt = Date()
            synchronizeTagColors(&notes)
            return notes[index]
        }
    }

    @discardableResult
    func delete(id: UUID) throws -> StickyNote {
        return try mutate { notes in
            guard let index = notes.firstIndex(where: { $0.id == id }) else {
                throw ServiceError.noteNotFound
            }
            return notes.remove(at: index)
        }
    }

    private func mutate<T>(_ change: (inout [StickyNote]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Atomic replacement changes the JSON inode, so lock a stable sidecar instead.
        let descriptor = open(fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { flock(descriptor, LOCK_UN) }
        var notes = try load()
        let result = try change(&notes)
        try save(notes)
        return result
    }

    // MARK: - Colour rules shared with the app

    private func chooseColor(for content: String, in notes: [StickyNote]) -> NoteColor {
        if let key = NoteText.primaryTagKey(in: content) {
            let members = notes.filter {
                NoteText.primaryTagKey(in: $0.content) == key
            }
            if let oldest = members.min(by: { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }) {
                return oldest.color
            }
        }
        let used = Set(notes.map(\.color))
        let unused = NoteColor.allCases.filter { !used.contains($0) }
        return (unused.isEmpty ? NoteColor.allCases : unused).randomElement() ?? .cream
    }

    private func synchronizeTagColors(_ notes: inout [StickyNote]) {
        var groupColors: [String: NoteColor] = [:]
        let oldestFirst = notes.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for note in oldestFirst {
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
}

enum ServiceError: LocalizedError {
    case noteNotFound
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .noteNotFound:
            return "No note with that id exists."
        case .invalidArguments(let message):
            return message
        }
    }
}
