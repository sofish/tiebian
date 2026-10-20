import AppKit
import SwiftUI
import EdgePeekCore

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct GlassBackground: View {
    var cornerRadius: CGFloat = 22
    var tintTop: Color = Theme.glassTop
    var tintBottom: Color = Theme.glassBottom

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
            LinearGradient(
                colors: [
                    tintTop.opacity(0.88),
                    tintBottom.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.24), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.7), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }
}

/// Clear glass: almost no tint, a lit rim and a cool specular sweep. A
/// material blur here would turn into a grey patch over the coloured paper,
/// so the glass is built from transparency and highlights instead.
struct LiquidGlassBackground<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape.fill(Color.white.opacity(0.035))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.17),
                        Color.white.opacity(0.015),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
        )
        .overlay(
            shape.inset(by: 1.5)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: Color.white.opacity(0.18), radius: 7, y: 1)
        .shadow(color: Theme.shadow.opacity(0.06), radius: 4, y: 2)
    }
}

struct PaperBackground: View {
    var color: NoteColor
    var cornerRadius: CGFloat = 12
    var highlighted: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color.paperTop)
    }
}

struct DashedRule: View {
    var color: Color = Theme.line.opacity(0.8)
    var dash: [CGFloat] = [3, 4]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 0.75, dash: dash))
        }
        .frame(height: 1)
    }
}


struct SoftIconButton: View {
    let systemName: String
    var help: String = ""
    var size: CGFloat = 11
    var activeColor: Color? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(activeColor ?? (hovering ? Theme.ink : Theme.inkSoft))
                .frame(width: 25, height: 25)
                .background(
                    Circle()
                        .fill(hovering ? Theme.ink.opacity(0.09) : Color.white.opacity(0.18))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.6)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PaperTexture: View {
    var opacity: Double = 0.035

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            var generator = LCG(seed: UInt64(size.width * 31 + size.height * 17))
            for _ in 0..<110 {
                let x = CGFloat(generator.next() % 10_000) / 10_000 * size.width
                let y = CGFloat(generator.next() % 10_000) / 10_000 * size.height
                let radius = 0.25 + CGFloat(generator.next() % 100) / 100 * 0.65
                let rect = CGRect(x: x, y: y, width: radius, height: radius)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.ink.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.multiply)
    }
}

private struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
