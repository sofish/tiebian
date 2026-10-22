import AppKit
import SwiftUI
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class NoteCardAppearanceTests: XCTestCase {
    func testReadingSizesNeverOverflowThePaper() {
        XCTAssertGreaterThanOrEqual(NoteCardMetrics.standard.contentSize, 12)
        for size in NoteFontSize.allCases {
            let metrics = NoteCardMetrics.metrics(for: size)
            let lineHeight = AppTypography.lineHeight(
                size: metrics.contentSize,
                spacing: NoteCardMetrics.contentSpacing
            )
            let used = CGFloat(metrics.contentLineLimit) * lineHeight
                - NoteCardMetrics.contentSpacing
            XCTAssertLessThanOrEqual(
                used,
                NoteCardMetrics.contentAreaHeight,
                "\(size.title) reserves more lines than the paper holds"
            )
            if size != .large {
                XCTAssertEqual(metrics.contentLineLimit, 4, "\(size.title)")
            }
        }
    }

    func testPreviewReservesOneLineOfTopWhitespaceAndLargerCopy() {
        for size in NoteFontSize.allCases {
            let metrics = NotePreviewMetrics.metrics(for: size)
            let lineHeight = AppTypography.lineHeight(
                size: metrics.contentSize,
                spacing: NotePreviewMetrics.spacing
            )
            XCTAssertEqual(metrics.topPadding, lineHeight, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(NotePreviewMetrics.standard.contentSize, 16.5)

        let note = StickyNote(content: "只有一行")
        let metrics = NotePreviewMetrics.standard
        XCTAssertEqual(
            NotePreviewView.estimatedHeight(for: note, metrics: metrics),
            metrics.chromeHeight + metrics.lineHeight,
            accuracy: 0.001
        )
    }

    func testReadingSizesScaleCardAndPreviewTogether() {
        let cardSizes = NoteFontSize.allCases.map { NoteCardMetrics.metrics(for: $0).contentSize }
        XCTAssertEqual(cardSizes, cardSizes.sorted())
        for size in NoteFontSize.allCases {
            XCTAssertEqual(NoteCardMetrics.metrics(for: size).contentSize, size.cardPointSize,
                           accuracy: 0.001)
            XCTAssertEqual(NotePreviewMetrics.metrics(for: size).contentSize, size.previewPointSize,
                           accuracy: 0.001)
        }
    }

    func testDraggedCardOnlyStampsDeleteWhenArmed() throws {
        let note = StickyNote(content: "拖动这张便签，看看纸上的删除印章。\n#工作")

        let paper = try bitmap(NoteCardPaper(note: note, paperColor: .cream))
        let idle = try bitmap(NoteCardDragPreview(note: note, paperColor: .cream))
        let armed = try bitmap(NoteCardDragPreview(note: note, paperColor: .cream, armed: true))

        let brush = accentRatio(paper)
        let idleBrush = accentRatio(idle)
        let armedBrush = accentRatio(armed)
        XCTAssertLessThan(brush, 0.005)
        XCTAssertLessThan(idleBrush, 0.005)
        XCTAssertGreaterThan(armedBrush, 0.01)
        XCTAssertGreaterThan(armedBrush, idleBrush + 0.01)
    }

    private func bitmap<V: View>(_ view: V) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let size = CGSize(width: BoardMetrics.cardWidth, height: BoardMetrics.cardHeight)
        let host = NSHostingView(rootView: view)
        // Render off-screen so the test never flashes a status-bar panel.
        let panel = PanelFactory.make(
            frame: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
            keyable: false
        )
        panel.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        panel.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { panel.orderOut(nil) }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// Fraction of pixels tinted like the deep accent-red stamp ink, far from
    /// both the warm paper and the dark brown body copy.
    private func accentRatio(_ bitmap: NSBitmapImageRep) -> Double {
        var tinted = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent - color.greenComponent > 0.18,
                   color.redComponent - color.blueComponent > 0.18,
                   color.alphaComponent > 0.25 {
                    tinted += 1
                }
            }
        }
        return Double(tinted) / Double(max(1, bitmap.pixelsHigh * bitmap.pixelsWide))
    }
}
