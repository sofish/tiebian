import EdgePeekCore
import SwiftUI

struct BoardActions {
    var openNote: (UUID) -> Void = { _ in }
    var toggleNotePin: (UUID) -> Void = { _ in }
    var setNoteDueDate: (UUID, Date?) -> Void = { _, _ in }
    var newNote: () -> Void = {}
    var cardDragBegan: (UUID) -> Void = { _ in }
    var cardDragMoved: (UUID, CGPoint) -> CardDropTarget = { _, _ in .none }
    var cardDragEnded: (UUID, CGPoint, Bool) -> Void = { _, _, _ in }
}

/// Board pages live outside the SwiftUI view so a note move can rebuild the
/// board without resetting the page, and so drop targeting knows which page
/// the person is looking at.
@MainActor
final class BoardPageState: ObservableObject {
    @Published private(set) var page = 0

    func go(to newPage: Int, pageCount: Int) {
        let clamped = min(max(0, newPage), max(0, pageCount - 1))
        guard clamped != page else { return }
        page = clamped
    }

    func clamp(to pageCount: Int) {
        go(to: page, pageCount: pageCount)
    }

    func reset() {
        go(to: 0, pageCount: 1)
    }
}

struct GroupBoardView: View {
    let layout: GroupBoardLayout
    let edge: EdgeSide
    let actions: BoardActions
    @ObservedObject var pageState: BoardPageState
    /// Resolved once per board build so each card body does not read
    /// UserDefaults again.
    let cardMetrics: NoteCardMetrics = .current

    @State private var appeared = false
    @State private var hoveredNoteID: UUID?

    private var page: Int { pageState.page }

    private var contentHeight: CGFloat {
        layout.pageSize.height - (layout.hasPager ? BoardMetrics.pagerHeight : 0)
    }
    private var pageGroups: [BoardGroupPlacement] {
        layout.pages[page] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if layout.entities.isEmpty {
                    emptyState
                } else {
                    ForEach(pageGroups) { group in
                        groupLabel(group)
                        ForEach(Array(group.cards.enumerated()), id: \.element.id) { index, card in
                            boardCard(card, group: group, index: index)
                        }
                    }
                }
            }
            .frame(
                width: layout.pageSize.width,
                height: contentHeight,
                alignment: .topLeading
            )
            .clipped()

            if layout.hasPager {
                pager
                    .frame(height: BoardMetrics.pagerHeight)
            }
        }
        .frame(width: layout.pageSize.width, height: layout.pageSize.height)
        .onAppear {
            withAnimation(Theme.spring) {
                appeared = true
            }
        }
        .onChange(of: layout.pageCount) { _, count in
            pageState.clamp(to: count)
        }
    }

    // MARK: - Group label

    private func groupLabel(_ group: BoardGroupPlacement) -> some View {
        let tag = group.entity.displayTag
        let labelAlignment: Alignment = edge == .right ? .trailing : .leading

        return VStack(alignment: .leading, spacing: 4) {
            if tag.isEmpty {
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(group.entity.color.dot.opacity(0.5))
                        .frame(width: 9, height: 1.5)
                    MixedText(
                        group.entity.displayName,
                        size: 8.2,
                        color: Theme.inkFaint
                    )
                }
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(group.entity.color.dot)
                        .frame(width: 4.5, height: 4.5)
                    MixedText(
                        tag,
                        size: 11.2,
                        weight: .medium,
                        color: Theme.ink.opacity(0.8),
                        lineLimit: 1
                    )
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.paper.opacity(0.78))
                        .shadow(color: Theme.shadow.opacity(0.08), radius: 4, y: 2)
                )
            }
        }
        .frame(
            width: group.labelFrame.width,
            height: group.labelFrame.height,
            alignment: labelAlignment
        )
        .position(
            x: group.labelFrame.midX,
            y: group.labelFrame.midY
        )
        .opacity(appeared ? 1 : 0)
        .animation(
            Theme.spring.delay(min(Double(group.slot) * 0.04, 0.22)),
            value: appeared
        )
    }

    // MARK: - Cards

    private func boardCard(
        _ card: BoardCardPlacement,
        group: BoardGroupPlacement,
        index: Int
    ) -> some View {
        let hovered = hoveredNoteID == card.note.id

        return NoteCardView(
            note: card.note,
            paperColor: group.entity.color,
            metrics: cardMetrics,
            isHovered: hovered,
            angle: card.rotation,
            onHover: { hovering in
                withAnimation(Theme.quickSpring) {
                    hoveredNoteID = hovering ? card.note.id : nil
                }
            },
            onOpen: { actions.openNote(card.note.id) },
            onTogglePin: { actions.toggleNotePin(card.note.id) },
            onSetDue: { actions.setNoteDueDate(card.note.id, $0) },
            onDragBegan: { actions.cardDragBegan(card.note.id) },
            onDragMoved: { actions.cardDragMoved(card.note.id, $0) },
            onDragEnded: { actions.cardDragEnded(card.note.id, $0, $1) }
        )
        .position(
            x: card.frame.midX,
            y: card.frame.midY
        )
        .offset(y: hovered ? -3 : 0)
        .zIndex(hovered ? 10_000 : Double(group.slot * 100 + index))
        .opacity(appeared ? 1 : 0)
        .offset(
            x: appeared ? 0 : edgeInwardOffset.width,
            y: appeared ? 0 : edgeInwardOffset.height
        )
        .animation(
            Theme.spring.delay(
                min(Double(group.slot) * 0.035 + Double(index) * 0.018, 0.28)
            ),
            value: appeared
        )
    }

    private var edgeInwardOffset: CGSize {
        switch edge {
        case .left: return CGSize(width: -18, height: 0)
        case .right: return CGSize(width: 18, height: 0)
        case .top: return CGSize(width: 0, height: -16)
        case .bottom: return CGSize(width: 0, height: 16)
        }
    }

    // MARK: - Pager

    private var pager: some View {
        HStack(spacing: 8) {
            pagerButton(systemName: "chevron.left", enabled: page > 0) {
                goToPage(page - 1)
            }
            Text("\(page + 1) / \(layout.pageCount)")
                .font(Theme.mono(8.2, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(minWidth: 40)
            pagerButton(systemName: "chevron.right", enabled: page < layout.pageCount - 1) {
                goToPage(page + 1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule()
                .fill(Theme.paper.opacity(0.78))
                .shadow(color: Theme.shadow.opacity(0.09), radius: 5, y: 2)
        )
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
    }

    private func pagerButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? Theme.inkSoft : Theme.inkFaint.opacity(0.35))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func goToPage(_ newPage: Int) {
        hoveredNoteID = nil
        withAnimation(Theme.quickSpring) {
            pageState.go(to: newPage, pageCount: layout.pageCount)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        Button(action: actions.newNote) {
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                MixedText("记一笔", size: 19, color: Theme.ink)
                Text("⌘ ⇧ Space")
                    .font(Theme.mono(7.2, weight: .regular))
                    .foregroundStyle(Theme.inkFaint)
            }
            .frame(width: 252, height: 124)
            .background(
                ZStack {
                    PaperBackground(color: .cream, cornerRadius: 6)
                    PaperTexture(opacity: 0.03)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.13), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .position(
            x: layout.pageSize.width / 2,
            y: contentHeight / 2
        )
    }
}
