import EdgePeekCore
import SwiftUI

@MainActor
final class SeamState: ObservableObject {
    @Published var edge: EdgeSide = .left
    @Published var width = SeamSizing.defaultWidth
    @Published var animation: SeamAnimation = .flow
    @Published var isHovered = false
    @Published var isDragging = false
    @Published var isSnapping = false
    @Published var hasDueNote = false
    @Published var noteCount = 0
    @Published var isBoardOpen = false
}
