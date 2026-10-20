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

    func testLabelsSitAboveTheirOwnStacksOnEveryEdge() throws {
        for edge in EdgeSide.allCases {
            let layout = GroupBoardLayout.make(
                entities: [group("长组", count: 5), group("短组", count: 1),
                           group("散页", count: 1, tagged: false)],
                edge: edge,
                screenSize: CGSize(width: 1440, height: 900)
            )
            for group in layout.groups {
                let firstCard = try XCTUnwrap(group.cards.first)
                XCTAssertEqual(group.labelFrame.minX, firstCard.frame.minX)
                XCTAssertEqual(group.labelFrame.width, firstCard.frame.width)
                XCTAssertEqual(firstCard.frame.minY - group.labelFrame.maxY,
                               BoardMetrics.labelGap)
                XCTAssertTrue(group.cards.allSatisfy { !$0.frame.intersects(group.labelFrame) })
            }
            // Short groups remain vertically centred, including their own header.
            let tall = try XCTUnwrap(layout.groups.first)
            let short = layout.groups[1]
            XCTAssertGreaterThan(short.labelFrame.minY, tall.labelFrame.minY)
            XCTAssertEqual(
                (short.labelFrame.minY + short.cards.last!.frame.maxY) / 2,
                (tall.labelFrame.minY + tall.cards.last!.frame.maxY) / 2
            )
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
            for group in layout.groups {
                let contentBounds = CGRect(
                    x: 0, y: 0, width: layout.pageSize.width,
                    height: layout.pageSize.height - BoardMetrics.pagerHeight
                )
                XCTAssertTrue(contentBounds.contains(group.labelFrame))
                XCTAssertTrue(group.cards.allSatisfy { contentBounds.contains($0.frame) })
                XCTAssertTrue(layout.pages[group.page]?.contains { $0.id == group.id } == true)
            }
            let heightRatio = edge.isVertical
                ? BoardMetrics.maximumHeightRatioVertical
                : BoardMetrics.maximumHeightRatioHorizontal
            XCTAssertLessThanOrEqual(layout.pageSize.height, ceil(700 * heightRatio))
        }
    }

    func testRightEdgeStillMirrorsColumnsWithHeaders() {
        let entities = [group("一", count: 1), group("二", count: 1)]
        let left = GroupBoardLayout.make(entities: entities, edge: .left,
                                        screenSize: CGSize(width: 1440, height: 900))
        let right = GroupBoardLayout.make(entities: entities, edge: .right,
                                         screenSize: CGSize(width: 1440, height: 900))
        XCTAssertEqual(left.groups.map(\.column), [0, 1])
        XCTAssertEqual(right.groups.map(\.column), [1, 0])
        XCTAssertEqual(left.groups[0].labelFrame, right.groups[1].labelFrame)
    }
}
