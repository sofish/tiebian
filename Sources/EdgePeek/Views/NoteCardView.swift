import EdgePeekCore
import SwiftUI

struct NoteCardView: View {
    let note: StickyNote
    let paperColor: NoteColor
    let isHovered: Bool
    let angle: Double
    let onHover: (Bool) -> Void
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onSetDue: (Date?) -> Void
    let onDragBegan: () -> Void
    let onDragMoved: (CGPoint) -> Void
    let onDragEnded: (CGPoint, Bool) -> Void

    private static let contentSize: CGFloat = 10.8
    private static let contentSpacing: CGFloat = 1.5
    private static let contentTopPadding: CGFloat = 9
    private static let contentBottomPadding: CGFloat = 7
    private static let footerHeight: CGFloat = 10
    private static let placeholder = "轻点，写下一点什么。"

    /// Fit as many wrapped content lines as the paper can hold. The first
    /// line is no longer a title, so nothing is reserved above the text.
    private static let contentLineLimit: Int = {
        let available = BoardMetrics.cardHeight
            - contentTopPadding
            - contentBottomPadding
            - footerHeight
        let lineHeight = AppTypography.lineHeight(size: contentSize, spacing: contentSpacing)
        return max(2, Int(floor((available + contentSpacing) / lineHeight)))
    }()

    var body: some View {
        card
        .frame(width: BoardMetrics.cardWidth, height: BoardMetrics.cardHeight)
        .rotationEffect(.degrees(isHovered ? 0 : angle), anchor: .center)
        .scaleEffect(isHovered ? 1.018 : 1)
        .shadow(
            color: Theme.shadow.opacity(isHovered ? 0.20 : 0.09),
            radius: isHovered ? 13 : 6,
            y: isHovered ? 7 : 3
        )
        .contentShape(Rectangle())
        .overlay {
            NoteCardDragSurface(noteID: note.id,
                                image: { ImageRenderer(content: card).nsImage },
                                onOpen: onOpen,
                                onDragBegan: onDragBegan,
                                onDragMoved: onDragMoved,
                                onDragEnded: onDragEnded)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .onHover(perform: onHover)
        .help("点击编辑；拖出便签板后松手删除，可撤销。\n" + note.plainText)
        .contextMenu {
            Button(action: onOpen) {
                Label("编辑便签", systemImage: "square.and.pencil")
            }
            Button(action: onTogglePin) {
                Label(note.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Menu {
                Button("1 小时后") {
                    onSetDue(Date().addingTimeInterval(60 * 60))
                }
                Button("明天 9:00") {
                    let calendar = Calendar.current
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    onSetDue(
                        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                            ?? tomorrow
                    )
                }
                if note.dueAt != nil {
                    Divider()
                    Button("清除提醒") {
                        onSetDue(nil)
                    }
                }
            } label: {
                Label("提醒时间", systemImage: "clock")
            }
        }
    }

    private var card: some View {
        let text = note.displayText
        let isEmpty = text.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            MixedText(
                isEmpty ? Self.placeholder : text,
                size: Self.contentSize,
                color: isEmpty ? Theme.inkFaint : Theme.ink,
                lineSpacing: Self.contentSpacing,
                lineLimit: Self.contentLineLimit
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                MixedText(
                    DateText.relative(note.updatedAt),
                    size: 7.2,
                    color: Theme.inkFaint,
                    lineLimit: 1
                )

                Spacer(minLength: 4)

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6.4, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }

                if let dueAt = note.dueAt {
                    DueBadge(date: dueAt)
                }
            }
            .frame(height: Self.footerHeight)
        }
        .padding(.horizontal, 13)
        .padding(.top, Self.contentTopPadding)
        .padding(.bottom, Self.contentBottomPadding)
        .frame(width: BoardMetrics.cardWidth, height: BoardMetrics.cardHeight, alignment: .topLeading)
        .background(
            ZStack(alignment: .topTrailing) {
                PaperBackground(color: paperColor, cornerRadius: 6)
                PaperTexture(opacity: 0.025)
                if note.isOverdue {
                    // The stamp sits under the copy like ink on paper, so it
                    // never steals a line from the note itself.
                    OverdueStamp()
                        .padding(.top, 7)
                        .padding(.trailing, 8)
                        .opacity(0.5)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct OverdueStamp: View {
    var body: some View {
        MixedText("过期", size: 9.4, weight: .medium, color: Theme.accentDeep)
            .tracking(2.2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Theme.accentDeep.opacity(0.72), lineWidth: 0.9)
            )
            .rotationEffect(.degrees(-8))
            .opacity(0.78)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

struct DueBadge: View {
    let date: Date
    private var overdue: Bool { date <= Date() }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 6.7, weight: .medium))
                .foregroundStyle(overdue ? Theme.accentDeep : Theme.inkSoft.opacity(0.9))
            MixedText(
                DateText.dueShort(date),
                size: 6.9,
                weight: .medium,
                color: overdue ? Theme.accentDeep : Theme.inkSoft.opacity(0.9),
                lineLimit: 1
            )
        }
    }
}
