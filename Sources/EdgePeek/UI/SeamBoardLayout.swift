import CoreGraphics
import EdgePeekCore
import Foundation

struct GroupEntity: Identifiable {
    let key: String
    let tag: String?
    let notes: [StickyNote]
    let color: NoteColor
    let angle: Double
    let isUntagged: Bool

    var id: String { key }
    var count: Int { notes.count }
    var displayTag: String { tag ?? "" }

    /// A column reads from the oldest note to the newest. Pinned notes stay
    /// near the top, where they can be seen without unfolding the column.
    var notesForColumn: [StickyNote] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

@MainActor
enum GroupDataSource {
    static func entities(for store: NoteStore) -> [GroupEntity] {
        store.noteGroups.map { group in
            let untagged = group.tag == nil
            let anchor = group.notes.min { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return GroupEntity(
                key: group.key,
                tag: group.tag,
                notes: group.notes,
                color: anchor?.color ?? .cream,
                angle: untagged
                    ? AngleHash.angle(for: group.key, range: -3.9...3.9)
                    : AngleHash.angle(for: group.key, range: -1.9...1.9),
                isUntagged: untagged
            )
        }
    }
}

enum AngleHash {
    static func value(for string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    static func angle(for key: String, range: ClosedRange<Double>) -> Double {
        let unit = Double(value(for: key) % 10_000) / 9_999
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

enum SeamMetrics {
    static func panelSize(edge: EdgeSide, length: CGFloat, width: CGFloat) -> CGSize {
        // Leave room inward for the overdue count; the outward glow meets the screen edge.
        let depth = max(24, inset(width: width) + countOffset(width: width) + 10)
        return edge.isVertical
            ? CGSize(width: depth, height: length)
            : CGSize(width: length, height: depth)
    }

    static func dotWidth(width: CGFloat, hasDue: Bool) -> CGFloat {
        width / SeamSizing.minimumWidth * (hasDue ? 5.2 : 3.6)
    }

    static func cometWidth(width: CGFloat, hasDue: Bool) -> CGFloat {
        width / SeamSizing.minimumWidth * (hasDue ? 4.2 : 3.1)
    }

    static func inset(width: CGFloat) -> CGFloat {
        width / 2
    }

    static func countOffset(width: CGFloat) -> CGFloat {
        max(9, dotWidth(width: width, hasDue: true) / 2 + 6)
    }

    static func lineCenter(edge: EdgeSide, size: CGSize, width: CGFloat) -> CGPoint {
        let offset = inset(width: width)
        switch edge {
        case .left: return CGPoint(x: offset, y: size.height / 2)
        case .right: return CGPoint(x: size.width - offset, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: offset)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height - offset)
        }
    }
}

enum BoardMetrics {
    static let cardWidth: CGFloat = 248
    static let cardHeight: CGFloat = 92
    static let cardGap: CGFloat = 10
    static let groupGap: CGFloat = 34
    static let labelHeight: CGFloat = 28
    static let labelGap: CGFloat = 12
    static let columnWidth: CGFloat = cardWidth
    static let boardPadding: CGFloat = 20
    static let pagerHeight: CGFloat = 34
    static let naturalStep: CGFloat = cardHeight + cardGap
    static let minimumStep: CGFloat = 4
    static let maximumWidthRatioVertical: CGFloat = 0.86
    static let maximumWidthRatioHorizontal: CGFloat = 0.90
    static let maximumHeightRatioVertical: CGFloat = 0.82
    static let maximumHeightRatioHorizontal: CGFloat = 0.70
}

struct BoardCardPlacement: Identifiable {
    let note: StickyNote
    let frame: CGRect
    let rotation: Double
    var id: UUID { note.id }
}

struct BoardGroupPlacement: Identifiable {
    let entity: GroupEntity
    let page: Int
    let column: Int
    let labelFrame: CGRect
    let cards: [BoardCardPlacement]
    var id: String { entity.key }
}

struct GroupBoardLayout {
    let entities: [GroupEntity]
    let groups: [BoardGroupPlacement]
    let pageCount: Int
    let columnsPerPage: Int
    let pageSize: CGSize
    let pages: [Int: [BoardGroupPlacement]]
    let commonHeight: CGFloat

    var hasPager: Bool { pageCount > 1 }

    static func make(
        entities: [GroupEntity],
        edge: EdgeSide,
        screenSize: CGSize
    ) -> GroupBoardLayout {
        guard !entities.isEmpty else {
            return GroupBoardLayout(
                entities: [],
                groups: [],
                pageCount: 1,
                columnsPerPage: 1,
                pageSize: CGSize(width: 320, height: 220),
                pages: [:],
                commonHeight: 150
            )
        }

        let maxBoardWidth = max(
            340,
            screenSize.width * (
                edge.isVertical
                    ? BoardMetrics.maximumWidthRatioVertical
                    : BoardMetrics.maximumWidthRatioHorizontal
            )
        )
        let maxBoardHeight = max(
            260,
            screenSize.height * (
                edge.isVertical
                    ? BoardMetrics.maximumHeightRatioVertical
                    : BoardMetrics.maximumHeightRatioHorizontal
            )
        )

        let capacityGuess = max(
            1,
            Int(
                floor(
                    (maxBoardWidth - BoardMetrics.boardPadding * 2 + BoardMetrics.groupGap)
                        / (BoardMetrics.columnWidth + BoardMetrics.groupGap)
                )
            )
        )
        let pageCountGuess = max(
            1,
            Int(ceil(Double(entities.count) / Double(capacityGuess)))
        )
        let pagerReserve = pageCountGuess > 1 ? BoardMetrics.pagerHeight : 0
        let availableHeight = max(
            BoardMetrics.cardHeight,
            maxBoardHeight - BoardMetrics.boardPadding * 2 - pagerReserve
                - BoardMetrics.labelHeight - BoardMetrics.labelGap
        )

        let maxCount = entities.map(\.count).max() ?? 1
        let step: CGFloat
        if maxCount <= 1 {
            step = BoardMetrics.naturalStep
        } else {
            let naturalHeight = BoardMetrics.cardHeight
                + CGFloat(maxCount - 1) * BoardMetrics.naturalStep
            if naturalHeight <= availableHeight {
                step = BoardMetrics.naturalStep
            } else {
                let fitStep = (availableHeight - BoardMetrics.cardHeight)
                    / CGFloat(maxCount - 1)
                step = max(BoardMetrics.minimumStep, fitStep)
            }
        }
        let commonHeight = BoardMetrics.cardHeight
            + CGFloat(max(0, maxCount - 1)) * step

        let columnsPerPage = min(capacityGuess, entities.count)
        let pageCount = max(
            1,
            Int(ceil(Double(entities.count) / Double(columnsPerPage)))
        )
        let pageColumns = pageCount > 1 ? columnsPerPage : entities.count
        let pageWidth = BoardMetrics.boardPadding * 2
            + CGFloat(pageColumns) * BoardMetrics.columnWidth
            + CGFloat(max(0, pageColumns - 1)) * BoardMetrics.groupGap
        let pageHeight = BoardMetrics.boardPadding * 2
            + BoardMetrics.labelHeight + BoardMetrics.labelGap
            + commonHeight
            + (pageCount > 1 ? BoardMetrics.pagerHeight : 0)

        var groups: [BoardGroupPlacement] = []
        for (index, entity) in entities.enumerated() {
            let page = index / columnsPerPage
            let pageColumn = index % columnsPerPage
            let displayedColumn = edge == .right
                ? (pageColumns - 1 - pageColumn)
                : pageColumn
            let columnX = BoardMetrics.boardPadding
                + CGFloat(displayedColumn) * (BoardMetrics.columnWidth + BoardMetrics.groupGap)

            let notes = entity.notesForColumn
            let stackHeight = BoardMetrics.cardHeight
                + CGFloat(max(0, notes.count - 1)) * step
            let groupTop = BoardMetrics.boardPadding
                + (commonHeight - stackHeight) / 2
            let stackTop = groupTop + BoardMetrics.labelHeight + BoardMetrics.labelGap

            let labelFrame = CGRect(
                x: columnX,
                y: groupTop,
                width: BoardMetrics.columnWidth,
                height: BoardMetrics.labelHeight
            )

            var cards: [BoardCardPlacement] = []
            for (noteIndex, note) in notes.enumerated() {
                cards.append(
                    BoardCardPlacement(
                        note: note,
                        frame: CGRect(
                            x: columnX,
                            y: stackTop + CGFloat(noteIndex) * step,
                            width: BoardMetrics.cardWidth,
                            height: BoardMetrics.cardHeight
                        ),
                        rotation: entity.angle
                    )
                )
            }

            groups.append(
                BoardGroupPlacement(
                    entity: entity,
                    page: page,
                    column: displayedColumn,
                    labelFrame: labelFrame,
                    cards: cards
                )
            )
        }

        var pages: [Int: [BoardGroupPlacement]] = [:]
        for group in groups {
            pages[group.page, default: []].append(group)
        }

        return GroupBoardLayout(
            entities: entities,
            groups: groups,
            pageCount: pageCount,
            columnsPerPage: pageColumns,
            pageSize: CGSize(
                width: ceil(pageWidth),
                height: ceil(pageHeight)
            ),
            pages: pages,
            commonHeight: ceil(commonHeight)
        )
    }
}
