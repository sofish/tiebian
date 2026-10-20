import AppKit
import SwiftUI
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class WindowDragHandleTests: XCTestCase {
    func testHandleMovesWindowWithoutDeletingAndCompletesOnlyOnMouseUp() throws {
        _ = NSApplication.shared
        let panel = PanelFactory.make(frame: CGRect(x: 100, y: 100, width: 300, height: 300),
                                      keyable: true)
        let handle = WindowDragHandleView(frame: CGRect(x: 0, y: 0, width: 184, height: 44))
        panel.contentView = handle
        var ended = false
        handle.onDragEnded = {
            ended = true
        }
        func event(_ type: NSEvent.EventType, screenPoint: NSPoint, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: panel.convertPoint(fromScreen: screenPoint), modifierFlags: [],
                timestamp: time, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ))
        }
        let down = try event(.leftMouseDown, screenPoint: NSPoint(x: 150, y: 120), time: 1)
        handle.mouseDown(with: down)
        handle.mouseDragged(with: try event(.leftMouseDragged,
            screenPoint: NSPoint(x: 350, y: 220), time: 1.01))
        XCTAssertEqual(panel.frame.origin, NSPoint(x: 300, y: 200))
        XCTAssertFalse(ended)
        // A second, rapid movement uses screen coordinates after the window moved.
        let finalPoint = NSPoint(x: -1950, y: 3020)
        handle.mouseDragged(with: try event(.leftMouseDragged, screenPoint: finalPoint, time: 1.02))
        XCTAssertEqual(panel.frame.origin, NSPoint(x: -2000, y: 3000))
        XCTAssertFalse(ended)
        handle.mouseUp(with: try event(.leftMouseUp, screenPoint: finalPoint, time: 1.03))
        XCTAssertTrue(ended)
        ended = false
        handle.mouseUp(with: try event(.leftMouseUp, screenPoint: finalPoint, time: 1.04))
        XCTAssertFalse(ended)
        XCTAssertTrue(handle.acceptsFirstMouse(for: down))
        panel.orderOut(nil)
    }

    func testDragHandleDoesNotCoverEditorControlsOrText() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekHitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"),
                              seedIfMissing: false)
        let note = store.addNote(content: "点一下收起，再设提醒\n#测试")
        let editor = EditorView(store: store, note: note, isNew: false,
                                onClose: {}, onDelete: {}, onDragEnded: {})
        let host = FirstMouseHostingView(rootView: editor)
        let panel = PanelFactory.make(
            frame: CGRect(origin: .zero, size: Layout.editorSize), keyable: true
        )
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        let handle = try XCTUnwrap(descendants(of: host).first { $0 is WindowDragHandleView })
        let handleFrame = host.convert(handle.bounds, from: handle)
        XCTAssertLessThanOrEqual(handleFrame.width, 184)
        // Coordinates are measured from the top of the editor, as in SwiftUI.
        func point(_ x: CGFloat, _ top: CGFloat) -> NSPoint {
            NSPoint(x: x, y: host.isFlipped ? top : host.bounds.height - top)
        }
        func hit(at point: NSPoint) -> NSView? {
            host.hitTest(host.convert(point, to: host.superview))
        }
        XCTAssertTrue(hit(at: point(285, 82)) === handle)
        for control in [point(425, 106), point(470, 106), point(455, 554), point(285, 250)] {
            XCTAssertFalse(handleFrame.contains(control))
            XCTAssertNotNil(hit(at: control))
            XCTAssertFalse(hit(at: control) is WindowDragHandleView)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
