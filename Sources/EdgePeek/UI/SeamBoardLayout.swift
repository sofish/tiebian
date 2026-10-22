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

    /// A group reads from the oldest note to the newest. Pinned notes stay
    /// first, where they can be seen without unfolding the stack.
    var orderedNotes: [StickyNote] {
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

    static func inset(width: CGFloat) -> CGFloat {
        width / 2
    }

    static func countOffset(width: CGFloat) -> CGFloat {
        max(9, width + 6)
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
    static let naturalRowStep: CGFloat = cardWidth + cardGap
    static let minimumStep: CGFloat = 4
    static let maximumWidthRatioVertical: CGFloat = 0.86
    static let maximumWidthRatioHorizontal: CGFloat = 0.90
    static let maximumHeightRatioVertical: CGFloat = 0.82
    static let maximumHeightRatioHorizontal: CGFloat = 0.70
}

enum BoardDragPolicy {
    /// Releasing a card this far outside the board deletes it.
    static let deletionMargin: CGFloat = 24

    static func isDeletionDistance(_ point: CGPoint, boardFrame: CGRect) -> Bool {
        !boardFrame.insetBy(dx: -deletionMargin, dy: -deletionMargin).contains(point)
    }
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
    /// Cross-axis position on the page: a row index for vertical seams and a
    /// column index for horizontal seams.
    let slot: Int
    let labelFrame: CGRect
    let cards: [BoardCardPlacement]
    /// Forgiving drop zone for dragging a card onto this group. Rows accept
    /// the whole band across the page; columns accept the whole height.
    let dropFrame: CGRect
    var id: String { entity.key }
}

struct GroupBoardLayout {
    let entities: [GroupEntity]
    let groups: [BoardGroupPlacement]
    let pageCount: Int
    let pageSize: CGSize
    let pages: [Int: [BoardGroupPlacement]]

    var hasPager: Bool { pageCount > 1 }

    func group(at point: CGPoint, page: Int) -> BoardGroupPlacement? {
        (pages[page] ?? []).first { $0.dropFrame.contains(point) }
    }

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
                pageSize: CGSize(width: 320, height: 220),
                pages: [:]
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

        return edge.isVertical
            ? makeRows(
                entities: entities,
                edge: edge,
                maxBoardWidth: maxBoardWidth,
                maxBoardHeight: maxBoardHeight
            )
            : makeColumns(
                entities: entities,
                edge: edge,
                maxBoardWidth: maxBoardWidth,
                maxBoardHeight: maxBoardHeight
            )
    }

    /// Fit the longest group into the available extent by compressing only the
    /// gaps between cards; full card size is the preferred state.
    private static func compressedStep(
        count: Int,
        cardExtent: CGFloat,
        availableExtent: CGFloat,
        naturalStep: CGFloat
    ) -> CGFloat {
        guard count > 1 else { return naturalStep }
        let naturalExtent = cardExtent + CGFloat(count - 1) * naturalStep
        guard naturalExtent > availableExtent else { return naturalStep }
        return max(
            BoardMetrics.minimumStep,
            (availableExtent - cardExtent) / CGFloat(count - 1)
        )
    }

    private static func pagedGroups(
        _ groups: [BoardGroupPlacement]
    ) -> [Int: [BoardGroupPlacement]] {
        Dictionary(grouping: groups, by: \.page)
    }

    /// Left/right seams read as rows: cards run horizontally, the label stays
    /// above the row, and rows hug the attached edge.
    private static func makeRows(
        entities: [GroupEntity],
        edge: EdgeSide,
        maxBoardWidth: CGFloat,
        maxBoardHeight: CGFloat
    ) -> GroupBoardLayout {
        let maxCount = entities.lazy.map(\.count).max() ?? 1
        let availableWidth = max(
            BoardMetrics.cardWidth,
            maxBoardWidth - BoardMetrics.boardPadding * 2
        )
        let step = compressedStep(
            count: maxCount,
            cardExtent: BoardMetrics.cardWidth,
            availableExtent: availableWidth,
            naturalStep: BoardMetrics.naturalRowStep
        )
        let maxRowWidth = BoardMetrics.cardWidth
            + CGFloat(max(0, maxCount - 1)) * step
        let rowHeight = BoardMetrics.labelHeight + BoardMetrics.labelGap
            + BoardMetrics.cardHeight
        let rowStride = rowHeight + BoardMetrics.groupGap
        let availableHeight = max(
            rowHeight,
            maxBoardHeight - BoardMetrics.boardPadding * 2
        )

        func rowsPerPage(reservingPager: Bool) -> Int {
            let height = reservingPager
                ? availableHeight - BoardMetrics.pagerHeight
                : availableHeight
            return max(
                1,
                Int(floor(
                    (max(rowHeight, height) + BoardMetrics.groupGap) / rowStride
                ))
            )
        }

        var slotsPerPage = min(rowsPerPage(reservingPager: false), entities.count)
        var pageCount = max(
            1,
            Int(ceil(Double(entities.count) / Double(slotsPerPage)))
        )
        if pageCount > 1 {
            slotsPerPage = rowsPerPage(reservingPager: true)
            pageCount = max(
                1,
                Int(ceil(Double(entities.count) / Double(slotsPerPage)))
            )
        }

        let rowsOnPage = pageCount > 1 ? slotsPerPage : entities.count
        let pageWidth = ceil(BoardMetrics.boardPadding * 2 + maxRowWidth)
        let pageHeight = ceil(
            BoardMetrics.boardPadding * 2
                + CGFloat(rowsOnPage) * rowHeight
                + CGFloat(max(0, rowsOnPage - 1)) * BoardMetrics.groupGap
                + (pageCount > 1 ? BoardMetrics.pagerHeight : 0)
        )

        var groups: [BoardGroupPlacement] = []
        for (index, entity) in entities.enumerated() {
            let page = index / slotsPerPage
            let slot = index % slotsPerPage
            let rowWidth = BoardMetrics.cardWidth
                + CGFloat(max(0, entity.count - 1)) * step
            let rowX = edge == .right
                ? pageWidth - BoardMetrics.boardPadding - rowWidth
                : BoardMetrics.boardPadding
            let rowY = BoardMetrics.boardPadding + CGFloat(slot) * rowStride
            let labelFrame = CGRect(
                x: rowX,
                y: rowY,
                width: rowWidth,
                height: BoardMetrics.labelHeight
            )
            let cardY = rowY + BoardMetrics.labelHeight + BoardMetrics.labelGap
            let notes = entity.orderedNotes

            var cards: [BoardCardPlacement] = []
            for (noteIndex, note) in notes.enumerated() {
                cards.append(
                    BoardCardPlacement(
                        note: note,
                        frame: CGRect(
                            x: rowX + CGFloat(noteIndex) * step,
                            y: cardY,
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
                    slot: slot,
                    labelFrame: labelFrame,
                    cards: cards,
                    dropFrame: CGRect(
                        x: 0,
                        y: rowY - BoardMetrics.groupGap / 2,
                        width: pageWidth,
                        height: rowHeight + BoardMetrics.groupGap
                    )
                )
            )
        }

        return GroupBoardLayout(
            entities: entities,
            groups: groups,
            pageCount: pageCount,
            pageSize: CGSize(width: pageWidth, height: pageHeight),
            pages: pagedGroups(groups)
        )
    }

    /// Top/bottom seams read as columns: cards run vertically, the label stays
    /// above the column, and short columns hug the attached edge instead of
    /// floating in the middle.
    private static func makeColumns(
        entities: [GroupEntity],
        edge: EdgeSide,
        maxBoardWidth: CGFloat,
        maxBoardHeight: CGFloat
    ) -> GroupBoardLayout {
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

        let maxCount = entities.lazy.map(\.count).max() ?? 1
        let step = compressedStep(
            count: maxCount,
            cardExtent: BoardMetrics.cardHeight,
            availableExtent: availableHeight,
            naturalStep: BoardMetrics.naturalStep
        )
        let tallestStack = BoardMetrics.cardHeight
            + CGFloat(max(0, maxCount - 1)) * step
        let blockHeight = BoardMetrics.labelHeight + BoardMetrics.labelGap
            + tallestStack

        let slotsPerPage = min(capacityGuess, entities.count)
        let pageCount = max(
            1,
            Int(ceil(Double(entities.count) / Double(slotsPerPage)))
        )
        let columnsOnPage = pageCount > 1 ? slotsPerPage : entities.count
        let pageWidth = ceil(
            BoardMetrics.boardPadding * 2
                + CGFloat(columnsOnPage) * BoardMetrics.columnWidth
                + CGFloat(max(0, columnsOnPage - 1)) * BoardMetrics.groupGap
        )
        let pageHeight = ceil(
            BoardMetrics.boardPadding * 2
                + blockHeight
                + (pageCount > 1 ? BoardMetrics.pagerHeight : 0)
        )
        let contentHeight = pageHeight
            - (pageCount > 1 ? BoardMetrics.pagerHeight : 0)

        var groups: [BoardGroupPlacement] = []
        for (index, entity) in entities.enumerated() {
            let page = index / slotsPerPage
            let slot = index % slotsPerPage
            let columnX = BoardMetrics.boardPadding
                + CGFloat(slot) * (BoardMetrics.columnWidth + BoardMetrics.groupGap)

            let notes = entity.orderedNotes
            let stackHeight = BoardMetrics.cardHeight
                + CGFloat(max(0, notes.count - 1)) * step
            let groupTop = edge == .bottom
                ? BoardMetrics.boardPadding + tallestStack - stackHeight
                : BoardMetrics.boardPadding
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
                    slot: slot,
                    labelFrame: labelFrame,
                    cards: cards,
                    dropFrame: CGRect(
                        x: columnX - BoardMetrics.groupGap / 2,
                        y: 0,
                        width: BoardMetrics.cardWidth + BoardMetrics.groupGap,
                        height: contentHeight
                    )
                )
            )
        }

        return GroupBoardLayout(
            entities: entities,
            groups: groups,
            pageCount: pageCount,
            pageSize: CGSize(width: pageWidth, height: pageHeight),
            pages: pagedGroups(groups)
        )
    }
}
