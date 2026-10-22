import EdgePeekCore
import SwiftUI

/// What releasing the dragged card at the pointer would do. The group case
/// carries the destination tag itself, so the same value both names the hint
/// and performs the drop; `nil` is the untagged group.
enum CardDropTarget: Equatable {
    case none
    case delete
    case group(String?)

    var title: String {
        switch self {
        case .none: return ""
        case .delete: return "松手删除"
        case .group(let tag): return "松手并入 \(tag ?? GroupEntity.untaggedName)"
        }
    }

    var systemImage: String {
        switch self {
        case .none, .delete: return "trash"
        case .group(let tag): return tag == nil ? "doc" : "number"
        }
    }
}

/// Places the drop hint against the dragged note instead of the middle of the
/// board, so the outcome stays attached to the paper the pointer is carrying.
enum CardDropHintLayout {
    static let gap: CGFloat = 8
    static let screenMargin: CGFloat = 8

    /// Prefer the slot under the card, flip above when the screen edge is too
    /// close, then keep the hint inside the screen either way.
    static func placement(
        cardFrame: CGRect,
        hintSize: CGSize,
        screenFrame: CGRect
    ) -> CGRect {
        let fitsBelow = cardFrame.minY - hintSize.height - gap
            >= screenFrame.minY + screenMargin
        let preferredY = fitsBelow
            ? cardFrame.minY - hintSize.height - gap
            : cardFrame.maxY + gap
        let y = EdgeGeometry.clamp(
            preferredY,
            lower: screenFrame.minY + screenMargin,
            upper: screenFrame.maxY - hintSize.height - screenMargin
        )
        let x = EdgeGeometry.clamp(
            cardFrame.midX - hintSize.width / 2,
            lower: screenFrame.minX + screenMargin,
            upper: screenFrame.maxX - hintSize.width - screenMargin
        )
        return CGRect(
            x: x.rounded(),
            y: y.rounded(),
            width: hintSize.width,
            height: hintSize.height
        )
    }
}

struct CardDropHint: View {
    let target: CardDropTarget

    private var isDelete: Bool { target == .delete }

    private var tint: Color {
        isDelete ? Theme.accentDeep : Theme.ink
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: target.systemImage)
                .font(.system(size: 11, weight: .semibold))
            MixedText(target.title, size: 12.5, weight: .medium, color: tint)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Capsule().fill(Theme.paper.opacity(0.97)))
        .overlay(
            Capsule().strokeBorder(
                isDelete ? Theme.accentDeep.opacity(0.55) : Theme.ink.opacity(0.22),
                lineWidth: 1
            )
        )
        .accessibilityLabel(target.title)
    }
}
