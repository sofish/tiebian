import EdgePeekCore
import SwiftUI

struct NotePreviewMetrics {
    static let spacing: CGFloat = 4
    static let minimumLines = 6
    /// Header, rule, footer and side/bottom padding. The blank first line is
    /// measured per reading size instead of being folded into this total.
    private static let fixedChromeHeight: CGFloat = 130

    let contentSize: CGFloat
    let lineHeight: CGFloat
    /// The preview opens with one blank line, so its top whitespace follows
    /// the copy's line height at every reading size.
    let topPadding: CGFloat
    let contentLineLimit: Int

    var chromeHeight: CGFloat { Self.fixedChromeHeight + topPadding }

    init(contentSize: CGFloat) {
        self.contentSize = contentSize
        let lineHeight = AppTypography.lineHeight(size: contentSize, spacing: Self.spacing)
        self.lineHeight = lineHeight
        topPadding = lineHeight
        contentLineLimit = max(
            Self.minimumLines,
            Int(floor((Layout.previewMaxHeight - Self.fixedChromeHeight - lineHeight) / lineHeight))
        )
    }

    /// Card sizes are resolved from the same reading-size preference, so a
    /// preset only has to be added to `NoteFontSize`.
    static func metrics(for size: NoteFontSize) -> NotePreviewMetrics {
        NotePreviewMetrics(contentSize: size.previewPointSize)
    }

    static let standard = metrics(for: .standard)

    static var current: NotePreviewMetrics {
        metrics(for: NoteFontPreferences().size)
    }
}

struct NotePreviewView: View {
    let note: StickyNote
    let edge: EdgeSide
    var onHover: (Bool) -> Void
    var onOpen: () -> Void

    private let content: String
    private let tags: [String]
    private let metrics: NotePreviewMetrics

    @State private var appeared = false

    /// Height used only when AppKit cannot measure the preview (for example
    /// before the view has a window). Keeps the fallback on the same metrics
    /// as the view instead of a second set of magic numbers.
    static func estimatedHeight(
        for note: StickyNote,
        metrics: NotePreviewMetrics = .current
    ) -> CGFloat {
        let lineCount = min(
            note.displayText.components(separatedBy: "\n").count,
            metrics.contentLineLimit
        )
        var height = metrics.chromeHeight
            + CGFloat(lineCount) * metrics.lineHeight
        if note.dueAt != nil { height += 8 }
        if !NoteText.tags(in: note.content).isEmpty { height += 22 }
        return height
    }

    init(
        note: StickyNote,
        edge: EdgeSide,
        onHover: @escaping (Bool) -> Void = { _ in },
        onOpen: @escaping () -> Void = {}
    ) {
        self.note = note
        self.edge = edge
        self.onHover = onHover
        self.onOpen = onOpen
        self.content = note.displayText
        self.tags = NoteText.tags(in: note.content)
        self.metrics = .current
    }

    var body: some View {
        Button(action: onOpen) {
            paper
            .frame(width: Layout.previewWidth)
            // A fractional hover scale resampled the whole paper, which made
            // the preview copy look soft next to the crisp card text.
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .onAppear {
            withAnimation(Theme.spring) {
                appeared = true
            }
        }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(note.color.dot)
                    .frame(width: 4.5, height: 4.5)
                Text("贴边 / NOTE")
                    .font(Theme.mono(7.4, weight: .semibold))
                    .tracking(1.2)
                Rectangle()
                    .fill(Theme.inkSoft.opacity(0.25))
                    .frame(width: 12, height: 0.6)
                Text(DateText.stamp(note.updatedAt))
                    .font(Theme.mono(7.4, weight: .regular))
                Spacer(minLength: 4)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(note.color.displayName)
                    .font(Theme.mono(7.2, weight: .regular))
            }
            .foregroundStyle(Theme.inkSoft.opacity(0.9))
            .padding(.top, 2)

            DashedRule(color: note.color.paperEdge.opacity(0.65))
                .padding(.top, 12)
                .padding(.bottom, 10)

            if content.isEmpty {
                Text("点开，写几句。")
                    .font(Theme.hand(metrics.contentSize))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.vertical, 2)
            } else {
                MixedText(
                    content,
                    size: metrics.contentSize,
                    color: Theme.ink,
                    lineSpacing: NotePreviewMetrics.spacing,
                    lineLimit: metrics.contentLineLimit
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(tags.prefix(4)), id: \.self) { tag in
                        Text(tag)
                            .font(Theme.mono(7.2, weight: .medium))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(Theme.accent.opacity(0.09))
                            )
                    }
                    if tags.count > 4 {
                        Text("+\(tags.count - 4)")
                            .font(Theme.mono(7, weight: .regular))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .padding(.top, 9)
            }

            HStack(spacing: 6) {
                if let dueAt = note.dueAt {
                    Image(systemName: "clock")
                        .font(.system(size: 7, weight: .medium))
                    Text(note.isOverdue ? "已到期 · \(DateText.dueFull(dueAt))" : DateText.dueFull(dueAt))
                        .font(Theme.mono(7.6, weight: note.isOverdue ? .semibold : .regular))
                        .lineLimit(1)
                } else {
                    Text("点击打开便签")
                        .font(Theme.mono(8, weight: .regular))
                }
                Spacer()
                Text("编辑")
                    .font(Theme.mono(8, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .foregroundStyle(
                note.isOverdue
                    ? Theme.accentDeep
                    : Theme.inkFaint
            )
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, 16)
        .frame(width: Layout.previewWidth)
        .background(PaperBackground(color: note.color, cornerRadius: 18))
        .overlay(alignment: .leading) {
            if note.isOverdue {
                Capsule()
                    .fill(Theme.accent.opacity(0.8))
                    .frame(width: 2.5)
                    .padding(.vertical, 14)
                    .padding(.leading, 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
