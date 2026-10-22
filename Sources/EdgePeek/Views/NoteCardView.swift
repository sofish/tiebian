import EdgePeekCore
import SwiftUI

struct NoteCardMetrics {
    static let contentSpacing: CGFloat = 1.5
    static let contentTopPadding: CGFloat = 7
    static let contentBottomPadding: CGFloat = 5
    static let footerHeight: CGFloat = 10
    static let placeholder = "轻点，写下一点什么。"

    static let contentAreaHeight: CGFloat =
        BoardMetrics.cardHeight - contentTopPadding - contentBottomPadding - footerHeight

    let contentSize: CGFloat
    /// Fit as many wrapped content lines as the paper can hold. The first
    /// line is no longer a title, so nothing is reserved above the text.
    let contentLineLimit: Int

    init(contentSize: CGFloat) {
        self.contentSize = contentSize
        let lineHeight = AppTypography.lineHeight(
            size: contentSize,
            spacing: Self.contentSpacing
        )
        contentLineLimit = max(
            2,
            Int(floor((Self.contentAreaHeight + Self.contentSpacing) / lineHeight))
        )
    }

    /// Font metrics are resolved once per reading size instead of on every
    /// card body, and a new preset only has to be added to `NoteFontSize`.
    private static let presets = Dictionary(
        uniqueKeysWithValues: NoteFontSize.allCases.map {
            ($0, NoteCardMetrics(contentSize: $0.cardPointSize))
        }
    )

    static let standard = metrics(for: .standard)

    static func metrics(for size: NoteFontSize) -> NoteCardMetrics {
        presets[size]!
    }

    static var current: NoteCardMetrics {
        metrics(for: NoteFontPreferences().size)
    }
}

struct NoteCardView: View {
    let note: StickyNote
    let paperColor: NoteColor
    let metrics: NoteCardMetrics
    let isHovered: Bool
    let angle: Double
    let onHover: (Bool) -> Void
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onSetDue: (Date?) -> Void
    let onDragBegan: () -> Void
    let onDragMoved: (CGPoint) -> CardDropTarget
    let onDragEnded: (CGPoint, Bool) -> Void

    var body: some View {
        NoteCardPaper(note: note, paperColor: paperColor, metrics: metrics)
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
                NoteCardDragSurface(
                    noteID: note.id,
                    image: { armed in
                        ImageRenderer(
                            content: NoteCardDragPreview(
                                note: note,
                                paperColor: paperColor,
                                metrics: metrics,
                                armed: armed
                            )
                        ).nsImage
                    },
                    onOpen: onOpen,
                    onDragBegan: onDragBegan,
                    onDragMoved: onDragMoved,
                    onDragEnded: onDragEnded
                )
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
}

/// The paper itself, shared by the resting card and the drag ghost so the two
/// can never drift apart.
struct NoteCardPaper: View {
    let note: StickyNote
    let paperColor: NoteColor
    var metrics: NoteCardMetrics = .standard

    var body: some View {
        let text = note.displayText
        let isEmpty = text.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            MixedText(
                isEmpty ? NoteCardMetrics.placeholder : text,
                size: metrics.contentSize,
                color: isEmpty ? Theme.inkFaint : Theme.ink,
                lineSpacing: NoteCardMetrics.contentSpacing,
                lineLimit: metrics.contentLineLimit
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                MixedText(
                    DateText.relative(note.updatedAt),
                    size: 7.8,
                    color: Theme.inkFaint,
                    lineLimit: 1
                )

                Spacer(minLength: 4)

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6.9, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }

                if let dueAt = note.dueAt {
                    DueBadge(date: dueAt)
                }
            }
            .frame(height: NoteCardMetrics.footerHeight)
        }
        .padding(.horizontal, 13)
        .padding(.top, NoteCardMetrics.contentTopPadding)
        .padding(.bottom, NoteCardMetrics.contentBottomPadding)
        .frame(width: BoardMetrics.cardWidth, height: BoardMetrics.cardHeight, alignment: .topLeading)
        .background(
            ZStack(alignment: .topTrailing) {
                PaperBackground(color: paperColor, cornerRadius: 6)
                PaperTexture(opacity: 0.025)
                if note.isOverdue {
                    // The stamp sits under the copy like ink on paper, so it
                    // never steals a line from the note itself.
                    PaperStamp(style: .overdue)
                        .padding(.top, 7)
                        .padding(.trailing, 8)
                        .opacity(0.5)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The ghost the pointer carries. A large "release to delete" stamp is
/// printed over the paper once the pointer is already outside the board, so
/// the destructive gesture is legible before the drop.
struct NoteCardDragPreview: View {
    let note: StickyNote
    let paperColor: NoteColor
    var metrics: NoteCardMetrics = .standard
    var armed = false

    var body: some View {
        NoteCardPaper(note: note, paperColor: paperColor, metrics: metrics)
            .overlay {
                if armed {
                    PaperStamp(style: .releaseToDelete)
                }
            }
    }
}

/// Ink stamps share one recipe; the presets differ only in weight and border.
private struct PaperStamp: View {
    struct Style {
        let text: String
        let size: CGFloat
        let tracking: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let cornerRadius: CGFloat
        let rotation: Double
        let opacity: Double
        let borderWidth: CGFloat
        let borderOpacity: CGFloat
        var innerBorderWidth: CGFloat = 0
        var innerBorderOpacity: CGFloat = 0
        var innerInset: CGFloat = 0
        var blendMode: BlendMode = .normal

        static let overdue = Style(
            text: "过期", size: 9.4, tracking: 2.2,
            horizontalPadding: 6, verticalPadding: 3, cornerRadius: 2.5,
            rotation: -8, opacity: 0.78, borderWidth: 0.9, borderOpacity: 0.72,
            blendMode: .multiply
        )
        static let releaseToDelete = Style(
            text: "放开即删除", size: 20, tracking: 4,
            horizontalPadding: 12, verticalPadding: 4, cornerRadius: 3,
            rotation: -9, opacity: 0.94, borderWidth: 1.6, borderOpacity: 0.86,
            innerBorderWidth: 0.6, innerBorderOpacity: 0.42, innerInset: 2.5
        )
    }

    let style: Style

    var body: some View {
        MixedText(style.text, size: style.size, weight: .medium, color: Theme.accentDeep)
            .tracking(style.tracking)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.accentDeep.opacity(style.borderOpacity),
                        lineWidth: style.borderWidth
                    )
            )
            .overlay {
                if style.innerBorderWidth > 0 {
                    RoundedRectangle(cornerRadius: style.cornerRadius - 1, style: .continuous)
                        .strokeBorder(
                            Theme.accentDeep.opacity(style.innerBorderOpacity),
                            lineWidth: style.innerBorderWidth
                        )
                        .padding(style.innerInset)
                }
            }
            .rotationEffect(.degrees(style.rotation))
            .opacity(style.opacity)
            .blendMode(style.blendMode)
            .allowsHitTesting(false)
    }
}

struct DueBadge: View {
    let date: Date
    private var overdue: Bool { date <= Date() }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 7.1, weight: .medium))
                .foregroundStyle(overdue ? Theme.accentDeep : Theme.inkSoft.opacity(0.9))
            MixedText(
                DateText.dueShort(date),
                size: 7.4,
                weight: .medium,
                color: overdue ? Theme.accentDeep : Theme.inkSoft.opacity(0.9),
                lineLimit: 1
            )
        }
    }
}
