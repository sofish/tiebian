import AppKit
import SwiftUI

final class PassiveEdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class KeyableEdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PanelFactory {
    static func make(frame: NSRect, keyable: Bool) -> NSPanel {
        let panel: NSPanel
        if keyable {
            // The editor is the one place that needs real keyboard focus.
            // `.nonactivatingPanel` keeps the app accessory-like, but it also
            // prevents the text view from becoming first responder reliably.
            panel = KeyableEdgePanel(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
        } else {
            panel = PassiveEdgePanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        return panel
    }
}


/// The note windows are non-activating panels. Without this, the first click
/// on a note in an inactive app is often consumed as an activation click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
