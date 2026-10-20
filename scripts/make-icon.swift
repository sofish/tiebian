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

// A single sheet emerging beside a warm edge light. Keep the silhouette
// clear at Finder and menu/dialog icon sizes.
let baseRect = NSRect(x: 58, y: 58, width: 908, height: 908)
let base = roundedPath(baseRect, radius: 218)
let outerShadow = NSShadow()
outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
outerShadow.shadowBlurRadius = 32
outerShadow.shadowOffset = NSSize(width: 0, height: -14)
fill(base, color(0x203D35), shadow: outerShadow)

NSGraphicsContext.saveGraphicsState()
base.addClip()
NSGradient(colors: [color(0x365C4E), color(0x152D28)])!.draw(
    from: NSPoint(x: 250, y: 980),
    to: NSPoint(x: 800, y: 80),
    options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
)
NSGraphicsContext.restoreGraphicsState()
stroke(roundedPath(baseRect.insetBy(dx: 1, dy: 1), radius: 217),
       NSColor.white.withAlphaComponent(0.12), width: 2)

let glowShadow = NSShadow()
glowShadow.shadowColor = color(0xE8A66A, alpha: 0.8)
glowShadow.shadowBlurRadius = 42
glowShadow.shadowOffset = .zero
fill(roundedPath(NSRect(x: 176, y: 258, width: 26, height: 508), radius: 13),
     color(0xEAB47E), shadow: glowShadow)
fill(roundedPath(NSRect(x: 183, y: 272, width: 7, height: 480), radius: 3.5),
     color(0xFFF1D1))

let paperShadow = NSShadow()
paperShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
paperShadow.shadowBlurRadius = 36
paperShadow.shadowOffset = NSSize(width: 0, height: -18)

rotated(-4, around: CGPoint(x: 562, y: 514)) {
    let paper = NSBezierPath()
    paper.move(to: NSPoint(x: 338, y: 242))
    paper.line(to: NSPoint(x: 786, y: 242))
    paper.curve(to: NSPoint(x: 818, y: 274),
                controlPoint1: NSPoint(x: 804, y: 242),
                controlPoint2: NSPoint(x: 818, y: 256))
    paper.line(to: NSPoint(x: 818, y: 680))
    paper.line(to: NSPoint(x: 706, y: 792))
    paper.line(to: NSPoint(x: 338, y: 792))
    paper.curve(to: NSPoint(x: 306, y: 760),
                controlPoint1: NSPoint(x: 320, y: 792),
                controlPoint2: NSPoint(x: 306, y: 778))
    paper.line(to: NSPoint(x: 306, y: 274))
    paper.curve(to: NSPoint(x: 338, y: 242),
                controlPoint1: NSPoint(x: 306, y: 256),
                controlPoint2: NSPoint(x: 320, y: 242))
    paper.close()
    fill(paper, color(0xFFF3D9), shadow: paperShadow)

    NSGraphicsContext.saveGraphicsState()
    paper.addClip()
    NSGradient(colors: [color(0xFFFAEC), color(0xECDDAD)])!.draw(
        from: NSPoint(x: 460, y: 800), to: NSPoint(x: 740, y: 240), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
    )
    NSGraphicsContext.restoreGraphicsState()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 706, y: 792))
    fold.line(to: NSPoint(x: 706, y: 708))
    fold.curve(to: NSPoint(x: 734, y: 680),
               controlPoint1: NSPoint(x: 706, y: 688),
               controlPoint2: NSPoint(x: 714, y: 680))
    fold.line(to: NSPoint(x: 818, y: 680))
    fold.close()
    let foldShadow = NSShadow()
    foldShadow.shadowColor = color(0x6E6846, alpha: 0.18)
    foldShadow.shadowBlurRadius = 12
    foldShadow.shadowOffset = NSSize(width: -4, height: -6)
    fill(fold, color(0xE3D19E), shadow: foldShadow)

    fill(roundedPath(NSRect(x: 380, y: 650, width: 152, height: 24), radius: 12),
         color(0xC57947))
    for (y, width): (CGFloat, CGFloat) in [(550, 300), (474, 250), (398, 288)] {
        fill(roundedPath(NSRect(x: 380, y: y, width: width, height: 18), radius: 9),
             color(0x3D5A4D, alpha: 0.56))
    }
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
