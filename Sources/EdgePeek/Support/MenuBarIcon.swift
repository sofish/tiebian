import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            // A slim edge-dwelling tab.
            let tab = NSBezierPath(
                roundedRect: NSRect(x: 3.2, y: 2.4, width: 4.6, height: 13.2),
                xRadius: 2.3,
                yRadius: 2.3
            )
            tab.fill()

            // Three small paper edges peeking out.
            for (index, y) in [10.8, 7.9, 5.0].enumerated() {
                let width = 7.5 - CGFloat(index) * 1.1
                let line = NSBezierPath(
                    roundedRect: NSRect(x: 10, y: y, width: width, height: 1.3),
                    xRadius: 0.65,
                    yRadius: 0.65
                )
                line.fill()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "贴边"
        return image
    }
}
