import XCTest
@testable import EdgePeekCore

final class NoteTagTests: XCTestCase {
    func testTagsAreExtractedAndColoursAreIgnored() {
        let content = "备忘\n用 #用法 和 #快捷键，颜色是 #C96F45。"
        let tags = NoteText.tags(in: content)
        XCTAssertEqual(tags, ["#用法", "#快捷键"])
    }

    func testTagsAreCaseInsensitiveAndDeduplicated() {
        let tags = NoteText.tags(in: "用 #Any 和 #any 分到一组。")
        XCTAssertEqual(tags, ["#Any"])
    }

    func testPrimaryTagIsTheFirstHashtag() {
        XCTAssertEqual(NoteText.primaryTag(in: "先 #用法 后 #快捷键"), "#用法")
        XCTAssertNil(NoteText.primaryTag(in: "没有标签"))
    }

    func testPureTagLinesAreHiddenFromCardBody() {
        let content = "标题\n第一行正文\n#用法"
        let lines = NoteText.bodyLinesForDisplay(from: content)
        XCTAssertEqual(lines.map(\.text), ["第一行正文"])
        XCTAssertEqual(NoteText.excerpt(from: content), "第一行正文")
    }

    func testTagOnlyContentIsEffectivelyEmpty() {
        XCTAssertTrue(NoteText.isEffectivelyEmpty("\n#用法\n#快捷键"))
        XCTAssertFalse(NoteText.isEffectivelyEmpty("\n#用法\n真的内容"))
    }

    func testMarkdownHeadingIsNotATag() {
        XCTAssertEqual(NoteText.tags(in: "# 标题\n## 二级标题"), [])
    }
}

final class StickyNoteCodableTests: XCTestCase {
    func testOldNoteWithoutDueDateStillDecodes() throws {
        let json = """
        [{
          "id": "9D6D0FB5-BC0D-47E6-A5E3-E11A33CDC43D",
          "content": "旧便签",
          "color": "cream",
          "isPinned": false,
          "createdAt": "2026-10-19T16:11:42Z",
          "updatedAt": "2026-10-19T16:11:42Z"
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notes = try decoder.decode([StickyNote].self, from: Data(json.utf8))
        XCTAssertEqual(notes.count, 1)
        XCTAssertNil(notes.first?.dueAt)
        XCTAssertEqual(notes.first?.content, "旧便签")
    }

    func testDueDateMakesNoteOverdue() {
        let past = Date().addingTimeInterval(-60)
        let note = StickyNote(content: "提醒", dueAt: past)
        XCTAssertTrue(note.isOverdue)
        XCTAssertTrue(note.hasDueDate)

        let future = StickyNote(content: "稍后", dueAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(future.isOverdue)
    }
}

@MainActor
final class NoteGroupingTests: XCTestCase {
    private func makeStore() throws -> (NoteStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekGroupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("notes.json")
        return (NoteStore(fileURL: url, seedIfMissing: false), directory)
    }

    func testGroupsByPrimaryTagAndKeepsUntaggedLast() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let base = Date()
        let first = store.addNote(
            content: "第一条\n#用法",
            color: .apricot,
            createdAt: base
        )
        let second = store.addNote(
            content: "第二条\n#用法\n#快捷键",
            color: .apricot,
            createdAt: base.addingTimeInterval(-10)
        )
        let third = store.addNote(
            content: "第三条\n#快捷键",
            color: .sky,
            createdAt: base.addingTimeInterval(-20)
        )
        let fourth = store.addNote(
            content: "没有标签",
            color: .rose,
            createdAt: base.addingTimeInterval(-30)
        )

        let groups = store.noteGroups
        XCTAssertEqual(
            groups.map(\.key),
            ["#用法", "#快捷键", "untagged:\(fourth.id.uuidString)"]
        )
        XCTAssertEqual(groups[0].notes.map(\.id), [first.id, second.id])
        XCTAssertEqual(groups[1].notes.map(\.id), [third.id])
        XCTAssertEqual(groups[2].notes.map(\.id), [fourth.id])
        XCTAssertNil(groups[2].tag)

        // Notes with the same primary tag share the group colour.
        XCTAssertEqual(store.note(with: first.id)?.color, .apricot)
        XCTAssertEqual(store.note(with: second.id)?.color, .apricot)

        // Changing one group member's colour changes the whole tag group.
        store.setColor(id: second.id, color: .rose)
        XCTAssertEqual(store.note(with: first.id)?.color, .rose)
        XCTAssertEqual(store.note(with: second.id)?.color, .rose)

        // Untagged notes are independent.
        store.setColor(id: fourth.id, color: .lilac)
        XCTAssertEqual(store.note(with: fourth.id)?.color, .lilac)
        XCTAssertEqual(store.note(with: third.id)?.color, .sky)
    }

    func testEveryUntaggedNoteIsItsOwnGroup() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = store.addNote(content: "没有标签的一")
        let second = store.addNote(content: "没有标签的二")
        let groups = store.noteGroups

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.notes.count), [1, 1])
        XCTAssertNil(groups[0].tag)
        XCTAssertNil(groups[1].tag)
        XCTAssertNotEqual(groups[0].key, groups[1].key)
        XCTAssertEqual(Set(groups.flatMap { $0.notes.map(\.id) }), Set([first.id, second.id]))
    }

    func testReloadsNotesChangedByAnotherProcess() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let note = store.addNote(content: "原来的内容\n#用法", color: .apricot)
        store.saveNow()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var onDisk = try decoder.decode(
            [StickyNote].self,
            from: Data(contentsOf: store.fileURL)
        )
        onDisk[0].content = "CLI 写的新内容\n#用法"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(onDisk).write(to: store.fileURL, options: .atomic)

        store.reloadFromDiskIfChanged()
        XCTAssertEqual(store.note(with: note.id)?.content, "CLI 写的新内容\n#用法")
    }

    func testNewNoteAdoptsTheExistingGroupColour() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let base = Date()
        let older = store.addNote(
            content: "旧的一条\n#用法",
            color: .apricot,
            createdAt: base.addingTimeInterval(-120)
        )
        let newer = store.addNote(
            content: "新的一条\n#用法",
            color: .rose,
            createdAt: base
        )

        XCTAssertEqual(store.note(with: older.id)?.color, .apricot)
        XCTAssertEqual(store.note(with: newer.id)?.color, .apricot)
    }

    func testDueDatesArePersistedAndReported() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let note = store.addNote(content: "交稿\n#工作")
        let due = Date().addingTimeInterval(-30)
        store.setDueDate(id: note.id, dueAt: due)
        XCTAssertTrue(store.hasOverdueNotes)
        XCTAssertEqual(store.overdueNotes.first?.id, note.id)
        store.saveNow()

        let reloaded = NoteStore(fileURL: store.fileURL, seedIfMissing: false)
        XCTAssertEqual(reloaded.note(with: note.id)?.dueAt?.timeIntervalSince1970 ?? 0,
                       due.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func testWelcomeNotesShowcaseTags() {
        let notes = NoteStore.welcomeNotes()
        let tags = notes.flatMap { NoteText.tags(in: $0.content) }
        XCTAssertTrue(tags.contains("#用法"))
        XCTAssertTrue(tags.contains("#快捷键"))
        XCTAssertTrue(tags.contains("#灵感"))
    }

    func testDeleteAndUndoRestoreAllFieldsAndPersistWithoutDuplicates() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = store.addNote(content: "要恢复的完整内容\n#工作", color: .rose)
        store.togglePin(id: note.id)
        store.setDueDate(id: note.id, dueAt: Date().addingTimeInterval(3600))
        let snapshot = try XCTUnwrap(store.note(with: note.id))

        store.delete(id: note.id)
        XCTAssertNil(store.note(with: note.id))
        store.restore(snapshot)
        store.restore(snapshot)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.note(with: note.id), snapshot)
        store.saveNow()

        let reloaded = NoteStore(fileURL: store.fileURL, seedIfMissing: false)
        XCTAssertEqual(reloaded.notes.count, 1)
        let restored = try XCTUnwrap(reloaded.note(with: note.id))
        XCTAssertEqual(restored.id, snapshot.id)
        XCTAssertEqual(restored.content, snapshot.content)
        XCTAssertEqual(restored.color, snapshot.color)
        XCTAssertEqual(restored.isPinned, snapshot.isPinned)
        XCTAssertEqual(try XCTUnwrap(restored.dueAt).timeIntervalSince1970,
                       try XCTUnwrap(snapshot.dueAt).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970,
                       snapshot.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.updatedAt.timeIntervalSince1970,
                       snapshot.updatedAt.timeIntervalSince1970, accuracy: 1)
    }
}
