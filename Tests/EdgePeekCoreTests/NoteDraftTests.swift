import XCTest
@testable import EdgePeekCore

@MainActor
final class NoteDraftTests: XCTestCase {
    private func makeStore() -> NoteStore {
        NoteStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekDraftTests-\(UUID().uuidString)/notes.json"), seedIfMissing: false)
    }

    func testWhitespaceDraftNeverPersistsAndIsDiscardedOnFinish() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let note = store.addNote()
        store.beginDraft(id: note.id)
        store.updateContent(id: note.id, content: " \t\n\r\u{3000}")
        store.togglePin(id: note.id)
        store.setDueDate(id: note.id, dueAt: Date())
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(NoteStore(fileURL: store.fileURL, seedIfMissing: false).notes.isEmpty)
        store.reloadFromDiskIfChanged()
        XCTAssertNotNil(store.note(with: note.id))
        store.finishDraft(id: note.id)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(NoteStore(fileURL: store.fileURL, seedIfMissing: false).notes.isEmpty)
    }

    func testDraftAutosavesRealContentAndErasingItRemovesPersistedCopy() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let note = store.addNote()
        store.beginDraft(id: note.id)
        store.updateContent(id: note.id, content: "想法\n#工作")
        store.saveNow()
        XCTAssertEqual(NoteStore(fileURL: store.fileURL).notes.first?.content, "想法\n#工作")
        store.updateContent(id: note.id, content: "\n  ")
        store.saveNow()
        XCTAssertTrue(NoteStore(fileURL: store.fileURL).notes.isEmpty)
        store.finishDraft(id: note.id)
        XCTAssertNil(store.note(with: note.id))
    }

    func testTagOnlyIsContentAndExistingEmptyNotesAreNotDiscarded() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let existing = store.addNote(content: "Existing")
        store.updateContent(id: existing.id, content: " ")
        let tag = store.addNote(content: "#工作")
        store.beginDraft(id: tag.id)
        store.finishDraft(id: tag.id)
        let reloaded = NoteStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.note(with: tag.id)?.content, "#工作")
        XCTAssertEqual(reloaded.note(with: existing.id)?.content, " ")
    }

    func testExternalWritesPreserveOpenDraftAndOtherNotes() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let note = store.addNote()
        store.beginDraft(id: note.id)
        let external = NoteStore(fileURL: store.fileURL, seedIfMissing: false)
        let other = external.addNote(content: "Agent added this")
        external.saveNow()
        store.reloadFromDiskIfChanged()
        XCTAssertNotNil(store.note(with: note.id))
        XCTAssertNotNil(store.note(with: other.id))
        store.updateContent(id: note.id, content: "正在写")
        try await Task.sleep(for: .milliseconds(450))
        store.reloadFromDiskIfChanged()
        XCTAssertEqual(store.note(with: note.id)?.content, "正在写")
        store.finishDraft(id: note.id)
        XCTAssertEqual(NoteStore(fileURL: store.fileURL).notes.count, 2)
    }
}
