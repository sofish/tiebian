import AppKit
import Foundation

// Draws the 1024 px master icon for 贴边 / EdgePeek.
// Run from the project root:
//   swift scripts/make-icon.swift Resources/icon-1024.png

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/icon-1024.png"

let scale: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(scale),
    pixelsHigh: Int(scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

rep.size = NSSize(width: scale, height: scale)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: scale, height: scale).fill()

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, _ fillColor: NSColor, shadow: NSShadow? = nil) {
    NSGraphicsContext.saveGraphicsState()
    if let shadow {
        shadow.set()
    }
    fillColor.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func stroke(_ path: NSBezierPath, _ strokeColor: NSColor, width: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func rotated(_ degrees: CGFloat, around point: CGPoint, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: point.x, yBy: point.y)
    transform.rotate(byDegrees: degrees)
    transform.translateX(by: -point.x, yBy: -point.y)
    transform.concat()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// Soft outer shadow behind the squircle.
let outerShadow = NSShadow()
outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
outerShadow.shadowBlurRadius = 42
outerShadow.shadowOffset = NSSize(width: 0, height: -20)

let baseRect = NSRect(x: 58, y: 58, width: 908, height: 908)
let base = roundedPath(baseRect, radius: 218)
fill(base, color(0xF8F0E1), shadow: outerShadow)

// Warm paper gradient.
NSGraphicsContext.saveGraphicsState()
base.addClip()
let gradient = NSGradient(colors: [
    color(0xFCF7ED),
    color(0xF3E6D2),
    color(0xE8D6BC)
])!
gradient.draw(
    from: NSPoint(x: 180, y: 900),
    to: NSPoint(x: 860, y: 100),
    options: []
)
NSGraphicsContext.restoreGraphicsState()

// Top glass highlight.
NSGraphicsContext.saveGraphicsState()
base.addClip()
let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.6),
    NSColor.white.withAlphaComponent(0.0)
])!
sheen.draw(
    from: NSPoint(x: 500, y: 940),
    to: NSPoint(x: 500, y: 560),
    options: []
)
NSGraphicsContext.restoreGraphicsState()

stroke(
    roundedPath(baseRect.insetBy(dx: 1, dy: 1), radius: 217),
    NSColor.white.withAlphaComponent(0.7),
    width: 2
)
stroke(
    roundedPath(baseRect, radius: 218),
    color(0x8D7355, alpha: 0.18),
    width: 1.5
)

// The seam the notes live on.
let glowShadow = NSShadow()
glowShadow.shadowColor = color(0xC96F45, alpha: 0.6)
glowShadow.shadowBlurRadius = 34
glowShadow.shadowOffset = .zero
fill(
    roundedPath(NSRect(x: 118, y: 276, width: 36, height: 472), radius: 18),
    color(0xC96F45),
    shadow: glowShadow
)

let seam = roundedPath(NSRect(x: 126, y: 294, width: 5, height: 436), radius: 2.5)
fill(seam, color(0xF4C5A8, alpha: 0.85))

// A stack of three paper notes.
let backShadow = NSShadow()
backShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
backShadow.shadowBlurRadius = 28
backShadow.shadowOffset = NSSize(width: 0, height: -12)

rotated(-8, around: CGPoint(x: 570, y: 490)) {
    let rect = NSRect(x: 340, y: 340, width: 470, height: 300)
    let path = roundedPath(rect, radius: 34)
    fill(path, color(0xDCE5CD), shadow: backShadow)
    stroke(roundedPath(rect.insetBy(dx: 1, dy: 1), radius: 33), NSColor.white.withAlphaComponent(0.45), width: 2)
}

rotated(5, around: CGPoint(x: 600, y: 500)) {
    let rect = NSRect(x: 390, y: 380, width: 480, height: 300)
    let path = roundedPath(rect, radius: 34)
    fill(path, color(0xF2D3BF), shadow: backShadow)
    stroke(roundedPath(rect.insetBy(dx: 1, dy: 1), radius: 33), NSColor.white.withAlphaComponent(0.45), width: 2)
}

rotated(-2.2, around: CGPoint(x: 605, y: 510)) {
    let rect = NSRect(x: 336, y: 250, width: 520, height: 430)
    let path = roundedPath(rect, radius: 36)
    fill(path, color(0xFBF5E9), shadow: backShadow)
    stroke(path, color(0xD9C7AC, alpha: 0.7), width: 2)

    // Tape.
    rotated(-3, around: CGPoint(x: 600, y: 678)) {
        fill(
            roundedPath(NSRect(x: 488, y: 650, width: 224, height: 44), radius: 4),
            color(0xBEB4A4, alpha: 0.72)
        )
    }

    // The small orange dot.
    let dot = NSBezierPath(ovalIn: NSRect(x: 390, y: 572, width: 30, height: 30))
    fill(dot, color(0xC96F45))

    // Handwritten-looking rules.
    let lineColor = color(0x6B5A48, alpha: 0.55)
    let widths: [CGFloat] = [392, 330, 360, 250]
    for (index, width) in widths.enumerated() {
        let y = 520 - CGFloat(index) * 66
        let line = roundedPath(NSRect(x: 390, y: y, width: width, height: 15), radius: 7.5)
        fill(line, lineColor)
    }

    // A tiny accent underline.
    let underline = roundedPath(NSRect(x: 390, y: 308, width: 124, height: 12), radius: 6)
    fill(underline, color(0xC96F45, alpha: 0.72))
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon.\n", stderr)
    exit(1)
}

do {
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
    print("Wrote \(outputPath)")
} catch {
    fputs("Could not write icon: \(error)\n", stderr)
    exit(1)
}
