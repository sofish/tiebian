import AppKit
import SwiftUI
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class BackgroundHoverTests: XCTestCase {
    func testResizingUpdatesWindowAndPersistsEvenWhenDisplayIsClamped() throws {
        _ = NSApplication.shared
        let name = "EdgePeekResizeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = SeamSizePreference(defaults: defaults)
        preference.length = 10_000
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"),
                              seedIfMissing: false)
        let controller = EdgeController(store: store, sizePreference: preference)
        defer { controller.shutdown() }
        let displayed = controller.seamLength
        XCTAssertLessThan(displayed, preference.length)
        controller.setSeamLength(displayed)
        XCTAssertEqual(preference.length, displayed)
        controller.setSeamLength(220)
        let seam = try XCTUnwrap(NSApp.windows.first {
            ($0.contentView as? NSHostingView<SeamView>)?.rootView.state === controller.seamState
        })
        let edge = controller.seamState.edge
        // EdgeGeometry rounds the complete frame out to integral screen points.
        XCTAssertEqual(edge.isVertical ? seam.frame.height : seam.frame.width, 220, accuracy: 1)
        controller.setSeamLength(SeamSizing.defaultLength)
        XCTAssertEqual(SeamSizePreference(defaults: defaults).length, 440)
    }

    func testInactiveAppOpensOnFirstHoverAndClosesAfterLeaving() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekHoverTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"),
                              seedIfMissing: false)
        store.addNote(content: "后台 hover\n#测试")
        var pointer = CGPoint(x: 100_000, y: 100_000)
        let controller = EdgeController(store: store, mouseLocation: { pointer })
        defer { controller.shutdown() }
        let seam = try XCTUnwrap(NSApp.windows.first {
            ($0.contentView as? NSHostingView<SeamView>)?.rootView.state === controller.seamState
        })
        NSApp.deactivate()
        pointer = CGPoint(x: seam.frame.midX, y: seam.frame.midY)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(NSApp.isActive)
        XCTAssertTrue(controller.seamState.isBoardOpen)
        let board = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentView is FirstMouseHostingView<AnyView>
        })
        XCTAssertFalse(board.canBecomeKey)

        pointer = CGPoint(x: 100_000, y: 100_000)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(controller.seamState.isBoardOpen)
        XCTAssertFalse(NSApp.isActive)
    }
}
