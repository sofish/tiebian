import AppKit
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class NoteEditorInteractionTests: XCTestCase {
    func testNewEditorDiscardsOnlyTrimmedEmptyContentBeforeSaving() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekEmptyEditorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"), seedIfMissing: false)
        let controller = NoteEditorController()
        defer { controller.close(restoreFocus: false) }
        for content in ["", " \n\t", "#标签", "有内容"] {
            let note = store.addNote()
            controller.open(note: note, isNew: true, store: store, on: screen) {}
            store.updateContent(id: note.id, content: content)
            controller.close(restoreFocus: false)
            let expected: String? = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
            XCTAssertEqual(store.note(with: note.id)?.content, expected)
            XCTAssertEqual(NoteStore(fileURL: store.fileURL, seedIfMissing: false).note(with: note.id)?.content, expected)
        }
    }

    func testExplicitDeleteAndUndoPersistThroughFileReload() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekEditorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"),
                              seedIfMissing: false)
        let controller = NoteEditorController()
        defer { controller.close(restoreFocus: false) }

        for content in ["删除后恢复\n#测试", "#只有标签", ""] {
            let note = store.addNote(content: content, color: .rose)
            store.saveNow()
            var dismissed = false
            controller.open(note: note, isNew: false, store: store, on: screen) {
                dismissed = true
            }
            let host = try XCTUnwrap(NSApp.windows.compactMap {
                $0.contentView as? FirstMouseHostingView<EditorView>
            }.first { $0.rootView.noteID == note.id })

            // Releasing even an off-screen drag only repositions the editor.
            host.window?.setFrameOrigin(NSPoint(x: -2000, y: 3000))
            host.rootView.onDragEnded()
            XCTAssertNotNil(store.note(with: note.id))
            XCTAssertTrue(controller.isOpen)

            host.rootView.onDelete()
            XCTAssertTrue(dismissed)
            XCTAssertFalse(controller.isOpen)
            store.reloadFromDiskIfChanged()
            XCTAssertNil(store.note(with: note.id))
            XCTAssertNil(NoteStore(fileURL: store.fileURL, seedIfMissing: false)
                .note(with: note.id))

            let toast = try XCTUnwrap(NSApp.windows.filter(\.isVisible).compactMap {
                $0.contentView as? FirstMouseHostingView<UndoToastView>
            }.first { $0.rootView.note.id == note.id })
            toast.rootView.onUndo()
            store.reloadFromDiskIfChanged()
            XCTAssertEqual(store.note(with: note.id)?.content, content)
            XCTAssertEqual(NoteStore(fileURL: store.fileURL, seedIfMissing: false)
                .note(with: note.id)?.content, content)
        }
    }
}
