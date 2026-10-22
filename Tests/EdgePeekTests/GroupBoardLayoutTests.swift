import XCTest
import EdgePeekCore
@testable import EdgePeek

final class GroupBoardLayoutTests: XCTestCase {
    private func group(_ key: String, count: Int, tagged: Bool = true) -> GroupEntity {
        GroupEntity(
            key: key,
            tag: tagged ? "#\(key)" : nil,
            notes: (0..<count).map { StickyNote(content: "便签 \($0)") },
            color: .cream,
            angle: 0,
            isUntagged: !tagged
        )
    }

    private let screen = CGSize(width: 1440, height: 900)

    func testVerticalSeamsLayCardsHorizontallyAndHugTheirEdge() throws {
        let entities = [group("长组", count: 3), group("短组", count: 1)]
        for edge in [EdgeSide.left, .right] {
            let layout = GroupBoardLayout.make(
                entities: entities,
                edge: edge,
                screenSize: screen
            )

            for placement in layout.groups {
                let firstCard = try XCTUnwrap(placement.cards.first)
                // Cards run horizontally, with the tag above the row.
                XCTAssertEqual(firstCard.frame.minY, placement.cards.last!.frame.minY)
                XCTAssertEqual(placement.labelFrame.maxY + BoardMetrics.labelGap,
                               firstCard.frame.minY)
                XCTAssertEqual(placement.cards.map(\.frame.minX),
                               placement.cards.map(\.frame.minX).sorted())
                XCTAssertEqual(placement.labelFrame.width,
                               placement.cards.last!.frame.maxX - firstCard.frame.minX)
                // Rows stack from the top instead of floating in a column.
                XCTAssertEqual(placement.labelFrame.minY,
                               BoardMetrics.boardPadding
                               + CGFloat(placement.slot) * (BoardMetrics.labelHeight
                                   + BoardMetrics.labelGap + BoardMetrics.cardHeight
                                   + BoardMetrics.groupGap))
            }

            if edge == .left {
                XCTAssertTrue(layout.groups.allSatisfy {
                    $0.labelFrame.minX == BoardMetrics.boardPadding
                        && $0.cards.first!.frame.minX == BoardMetrics.boardPadding
                })
            } else {
                XCTAssertTrue(layout.groups.allSatisfy {
                    $0.labelFrame.maxX == layout.pageSize.width - BoardMetrics.boardPadding
                        && $0.cards.last!.frame.maxX
                            == layout.pageSize.width - BoardMetrics.boardPadding
                })
            }
        }
    }

    func testHorizontalSeamsLayCardsVerticallyAndHugTheirEdge() throws {
        let entities = [group("长组", count: 5), group("短组", count: 1)]
        for edge in [EdgeSide.top, .bottom] {
            let layout = GroupBoardLayout.make(
                entities: entities,
                edge: edge,
                screenSize: screen
            )

            for placement in layout.groups {
                let firstCard = try XCTUnwrap(placement.cards.first)
                XCTAssertEqual(firstCard.frame.minX, placement.cards.last!.frame.minX)
                XCTAssertEqual(placement.labelFrame.maxY + BoardMetrics.labelGap,
                               firstCard.frame.minY)
                XCTAssertEqual(placement.cards.map(\.frame.minY),
                               placement.cards.map(\.frame.minY).sorted())
            }

            let tall = try XCTUnwrap(layout.groups.first)
            let short = layout.groups[1]
            if edge == .top {
                XCTAssertEqual(tall.labelFrame.minY, BoardMetrics.boardPadding)
                XCTAssertEqual(short.labelFrame.minY, BoardMetrics.boardPadding)
            } else {
                let contentBottom = layout.pageSize.height
                    - (layout.hasPager ? BoardMetrics.pagerHeight : 0)
                    - BoardMetrics.boardPadding
                XCTAssertEqual(tall.cards.last!.frame.maxY, contentBottom)
                XCTAssertEqual(short.cards.last!.frame.maxY, contentBottom)
                XCTAssertGreaterThan(short.labelFrame.minY, tall.labelFrame.minY)
            }
        }
    }

    func testHeaderSpaceIsReservedBeforeCompressingAndPaginating() {
        for edge in EdgeSide.allCases {
            let layout = GroupBoardLayout.make(
                entities: (0..<7).map { group("组\($0)", count: 12) },
                edge: edge,
                screenSize: CGSize(width: 900, height: 700)
            )
            XCTAssertTrue(layout.hasPager)
            XCTAssertEqual(layout.groups.count, 7)
            for placement in layout.groups {
                let contentBounds = CGRect(
                    x: 0, y: 0, width: layout.pageSize.width,
                    height: layout.pageSize.height - BoardMetrics.pagerHeight
                )
                XCTAssertTrue(contentBounds.contains(placement.labelFrame))
                XCTAssertTrue(placement.cards.allSatisfy { contentBounds.contains($0.frame) })
                XCTAssertTrue(
                    layout.pages[placement.page]?.contains { $0.id == placement.id } == true
                )
                // The tag keeps its place above the stack on every edge.
                XCTAssertLessThanOrEqual(placement.labelFrame.maxY,
                                         placement.cards.first!.frame.minY)
            }
            let widthRatio = edge.isVertical
                ? BoardMetrics.maximumWidthRatioVertical
                : BoardMetrics.maximumWidthRatioHorizontal
            let heightRatio = edge.isVertical
                ? BoardMetrics.maximumHeightRatioVertical
                : BoardMetrics.maximumHeightRatioHorizontal
            XCTAssertLessThanOrEqual(layout.pageSize.width, ceil(900 * widthRatio))
            XCTAssertLessThanOrEqual(layout.pageSize.height, ceil(700 * heightRatio))
        }
    }

    func testDropZonesCoverRowsAndColumnsPerPage() throws {
        let rows = GroupBoardLayout.make(
            entities: [group("一", count: 3), group("二", count: 1)],
            edge: .left,
            screenSize: screen
        )
        XCTAssertNotNil(rows.group(at: CGPoint(x: 120, y: 80), page: 0))
        // A row accepts drops across the whole page width, not just on cards.
        let secondRow = CGPoint(
            x: rows.pageSize.width - 30,
            y: rows.groups[1].labelFrame.midY
        )
        XCTAssertEqual(rows.group(at: secondRow, page: 0)?.entity.tag, "#二")
        XCTAssertNil(rows.group(at: secondRow, page: 1))

        let columns = GroupBoardLayout.make(
            entities: [group("一", count: 1), group("二", count: 1)],
            edge: .top,
            screenSize: screen
        )
        let secondColumn = CGPoint(
            x: columns.groups[1].labelFrame.midX,
            y: columns.pageSize.height - 20
        )
        XCTAssertEqual(columns.group(at: secondColumn, page: 0)?.entity.tag, "#二")
        XCTAssertEqual(
            columns.group(at: CGPoint(x: 30, y: 100), page: 0)?.entity.tag,
            "#一"
        )
    }
}
