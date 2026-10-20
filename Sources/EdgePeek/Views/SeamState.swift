import EdgePeekCore
import SwiftUI

@MainActor
final class SeamState: ObservableObject {
    @Published var edge: EdgeSide = .left
    @Published var isHovered = false
    @Published var isDragging = false
    @Published var isSnapping = false
    @Published var hasDueNote = false
    @Published var overdueCount = 0
    @Published var isBoardOpen = false
}
