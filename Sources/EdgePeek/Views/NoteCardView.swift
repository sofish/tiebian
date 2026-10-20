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

    private var title: String {
        let value = note.displayTitle
        return value.isEmpty ? "空白便签" : value
    }

    private var excerpt: String {
        let text = note.excerpt
        if !text.isEmpty { return text }
        return note.plainText.isEmpty ? "轻点，写下一点什么。" : ""
    }

    var body: some View {
        Button(action: onOpen) {
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
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .help(note.plainText.isEmpty ? "空白便签" : note.plainText)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                MixedText(
                    title,
                    size: 16,
                    weight: .medium,
                    color: Theme.ink,
                    lineLimit: 1
                )

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6.4, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer(minLength: 5)

                if note.isOverdue {
                    // Reserved space for the single ink stamp, so a long title
                    // never runs underneath it.
                    Spacer()
                        .frame(width: 36)
                } else if let dueAt = note.dueAt {
                    DueBadge(date: dueAt)
                }
            }

            if !excerpt.isEmpty {
                MixedText(
                    excerpt,
                    size: 11.2,
                    color: Theme.inkSoft,
                    lineSpacing: 3,
                    lineLimit: 2
                )
                .padding(.top, 5)
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                MixedText(
                    DateText.relative(note.updatedAt),
                    size: 7.2,
                    color: Theme.inkFaint,
                    lineLimit: 1
                )

                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(width: BoardMetrics.cardWidth, height: BoardMetrics.cardHeight, alignment: .topLeading)
        .background(
            ZStack {
                PaperBackground(color: paperColor, cornerRadius: 6)
                PaperTexture(opacity: 0.025)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if note.isOverdue {
                OverdueStamp()
                    .padding(.top, 7)
                    .padding(.trailing, 8)
            }
        }
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
