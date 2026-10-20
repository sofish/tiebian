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
        let preference = SeamPreferences(defaults: defaults)
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
        XCTAssertEqual(SeamPreferences(defaults: defaults).length, 440)
        controller.setSeamWidth(SeamSizing.widthRange.upperBound)
        XCTAssertEqual(controller.seamState.width, SeamSizing.widthRange.upperBound)
        let expected = SeamMetrics.panelSize(edge: edge, length: controller.seamLength,
                                            width: controller.seamWidth)
        XCTAssertEqual(seam.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(seam.frame.height, expected.height, accuracy: 1)
        XCTAssertEqual(SeamPreferences(defaults: defaults).width, controller.seamWidth)
    }

    func testManualAllNotesStaysOpenAwayFromEdgeAndTogglesWithoutActivating() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekAllNotesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(fileURL: directory.appendingPathComponent("notes.json"), seedIfMissing: false)
        store.addNote(content: "一\n#工作")
        store.addNote(content: "二\n#灵感")
        let controller = EdgeController(store: store, mouseLocation: { CGPoint(x: 100_000, y: 100_000) })
        defer { controller.shutdown() }
        controller.createNote()
        let draftID = try XCTUnwrap(controller.editor.editingNoteID)
        NSApp.deactivate()
        controller.toggleAllNotes()
        XCTAssertFalse(controller.editor.isOpen)
        XCTAssertNil(store.note(with: draftID))
        XCTAssertTrue(controller.seamState.isBoardOpen)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(controller.seamState.isBoardOpen)
        XCTAssertFalse(NSApp.isActive)
        controller.toggleAllNotes()
        XCTAssertFalse(controller.seamState.isBoardOpen)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(controller.seamState.isBoardOpen)
    }

    func testHorizonAndCountHaveRoomAtEveryWidthAndEdge() {
        for edge in EdgeSide.allCases {
            for width in [SeamSizing.minimumWidth, SeamSizing.defaultWidth, SeamSizing.widthRange.upperBound] {
                let size = SeamMetrics.panelSize(edge: edge, length: 440, width: width)
                let center = SeamMetrics.lineCenter(edge: edge, size: size, width: width)
                let inset = edge.isVertical ? center.x : center.y
                let depth = edge.isVertical ? size.width : size.height
                let outward = edge == .left || edge == .top ? inset : depth - inset
                XCTAssertEqual(outward - width / 2, 0, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(depth, 24)
                XCTAssertLessThanOrEqual(outward + SeamMetrics.countOffset(width: width) + 10, depth + 0.001)
            }
        }
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
        seam.contentView?.layoutSubtreeIfNeeded()
        let glow = try XCTUnwrap(seam.childWindows?.first { $0.ignoresMouseEvents })
        switch controller.seamState.edge {
        case .left: pointer = CGPoint(x: glow.frame.maxX - 8, y: seam.frame.midY)
        case .right: pointer = CGPoint(x: glow.frame.minX + 8, y: seam.frame.midY)
        case .top: pointer = CGPoint(x: seam.frame.midX, y: glow.frame.minY + 8)
        case .bottom: pointer = CGPoint(x: seam.frame.midX, y: glow.frame.maxY - 8)
        }
        XCTAssertFalse(seam.frame.insetBy(dx: -6, dy: -6).contains(pointer))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(controller.seamState.isBoardOpen)
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
