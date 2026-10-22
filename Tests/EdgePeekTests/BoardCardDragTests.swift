import AppKit
import SwiftUI
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class BoardCardDragTests: XCTestCase {
    func testHoverBoardStaysOpenDuringDragAndOnlyOutsideReleaseDeletesWithUndo() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekCardDragTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"), seedIfMissing: false)
        let note = store.addNote(content: "拖出删除\n#工作", color: .rose)
        let sibling = store.addNote(content: "留在组里\n#工作")
        store.togglePin(id: note.id)
        store.setDueDate(id: note.id, dueAt: Date().addingTimeInterval(3600))
        let snapshot = try XCTUnwrap(store.note(with: note.id))
        var pointer = CGPoint(x: 100_000, y: 100_000)
        let controller = EdgeController(store: store, mouseLocation: { pointer })
        defer { controller.shutdown() }
        let seam = try XCTUnwrap(NSApp.windows.first {
            ($0.contentView as? NSHostingView<SeamView>)?.rootView.state === controller.seamState
        })
        pointer = CGPoint(x: seam.frame.midX, y: seam.frame.midY)
        try await Task.sleep(for: .milliseconds(400))
        let board = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentView is FirstMouseHostingView<AnyView>
        })
        let inside = CGPoint(x: board.frame.midX, y: board.frame.midY)
        let outside = CGPoint(x: board.frame.maxX + 200, y: board.frame.maxY + 200)
        controller.cardDragBegan(noteID: note.id)
        controller.cardDragMoved(noteID: note.id, at: inside)
        XCTAssertFalse(controller.boardDragState.isDeleteArmed)
        controller.cardDragMoved(noteID: note.id, at: outside)
        XCTAssertTrue(controller.boardDragState.isDeleteArmed)
        controller.cardDragMoved(noteID: note.id, at: inside)
        XCTAssertFalse(controller.boardDragState.isDeleteArmed)
        pointer = outside
        controller.cardDragMoved(noteID: note.id, at: outside)
        XCTAssertTrue(controller.boardDragState.isDeleteArmed)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(controller.seamState.isBoardOpen)
        controller.cardDragEnded(noteID: note.id, at: outside, cancelled: true)
        XCTAssertFalse(controller.boardDragState.isDeleteArmed)
        XCTAssertEqual(store.note(with: note.id), snapshot)

        controller.cardDragBegan(noteID: note.id)
        controller.cardDragEnded(noteID: note.id, at: inside, cancelled: false)
        XCTAssertEqual(store.note(with: note.id), snapshot)
        controller.cardDragBegan(noteID: note.id)
        controller.cardDragEnded(noteID: note.id, at: outside, cancelled: false)
        XCTAssertNil(store.note(with: note.id))
        XCTAssertNotNil(store.note(with: sibling.id))
        XCTAssertNil(NoteStore(fileURL: store.fileURL).note(with: note.id))
        let toast = try XCTUnwrap(NSApp.windows.filter(\.isVisible).compactMap {
            $0.contentView as? FirstMouseHostingView<UndoToastView>
        }.first { $0.rootView.note.id == note.id })
        toast.rootView.onUndo()
        XCTAssertEqual(store.note(with: note.id), snapshot)
        let restored = try XCTUnwrap(NoteStore(fileURL: store.fileURL).note(with: note.id))
        XCTAssertEqual(restored.id, snapshot.id)
        XCTAssertEqual(restored.isPinned, snapshot.isPinned)
        XCTAssertEqual(restored.dueAt?.timeIntervalSince1970 ?? 0,
                       snapshot.dueAt?.timeIntervalSince1970 ?? 0, accuracy: 1)
    }

    func testDroppingCardOnAnotherGroupChangesItsTag() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekCardRetagTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"), seedIfMissing: false)
        let target = store.addNote(content: "目标\n#灵感", color: .sky)
        let note = store.addNote(content: "移动我\n#工作", color: .rose)
        var pointer = CGPoint(x: 100_000, y: 100_000)
        let controller = EdgeController(store: store, mouseLocation: { pointer })
        defer { controller.shutdown() }
        let seam = try XCTUnwrap(NSApp.windows.first {
            ($0.contentView as? NSHostingView<SeamView>)?.rootView.state === controller.seamState
        })
        pointer = CGPoint(x: seam.frame.midX, y: seam.frame.midY)
        try await Task.sleep(for: .milliseconds(400))
        let board = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentView is FirstMouseHostingView<AnyView>
        })
        let layout = try XCTUnwrap(controller.boardLayout)
        let targetGroup = try XCTUnwrap(layout.groups.first { $0.entity.tag == "#灵感" })
        let local = CGPoint(x: targetGroup.labelFrame.midX, y: targetGroup.labelFrame.midY)
        let drop = CGPoint(x: board.frame.minX + local.x, y: board.frame.maxY - local.y)

        controller.cardDragBegan(noteID: note.id)
        controller.cardDragEnded(noteID: note.id, at: drop, cancelled: false)

        let moved = try XCTUnwrap(store.note(with: note.id))
        XCTAssertEqual(NoteText.primaryTag(in: moved.content), "#灵感")
        XCTAssertEqual(moved.content, "移动我\n#灵感")
        XCTAssertEqual(moved.color, .sky)
        XCTAssertEqual(store.note(with: target.id)?.content, "目标\n#灵感")
    }

    func testNativeCardClickOpensOnlyAfterInsideMouseRelease() throws {
        _ = NSApplication.shared
        let panel = PanelFactory.make(frame: NSRect(x: 0, y: 0, width: 248, height: 92), keyable: false)
        let view = NoteCardDragView(frame: NSRect(x: 0, y: 0, width: 248, height: 92))
        panel.contentView = view
        defer { panel.orderOut(nil) }
        var opened = 0
        view.onOpen = { opened += 1 }
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 0))
        }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        XCTAssertEqual(opened, 0)
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 20, y: 20)))
        XCTAssertEqual(opened, 1)
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 500, y: 500)))
        XCTAssertEqual(opened, 1)
    }
}
