import AppKit
import EdgePeekCore
import SwiftUI

@MainActor
final class UndoToastController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var note: StickyNote?
    private var undoHandler: ((StickyNote) -> Void)?

    func show(
        note: StickyNote,
        on screen: NSScreen,
        undo: @escaping (StickyNote) -> Void
    ) {
        hide(immediately: true)
        self.note = note
        self.undoHandler = undo

        let size = CGSize(width: 342, height: 76)
        let visible = screen.visibleFrame
        let frame = CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + 28).rounded(),
            width: size.width,
            height: size.height
        )

        let panel = PanelFactory.make(frame: frame, keyable: false)
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0

        let view = UndoToastView(
            note: note,
            onUndo: { [weak self] in self?.performUndo() },
            onDismiss: { [weak self] in self?.hide() }
        )
        let host = FirstMouseHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()

        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: work)
    }

    func hide(immediately: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        undoHandler = nil
        note = nil

        guard let panel else { return }
        self.panel = nil

        if immediately {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func performUndo() {
        guard let note, let undoHandler else { return }
        undoTarget(note: note, handler: undoHandler)
    }

    private func undoTarget(note: StickyNote, handler: (StickyNote) -> Void) {
        handler(note)
        hide()
    }
}

private struct UndoToastView: View {
    let note: StickyNote
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var hoveringUndo = false
    @State private var hoveringClose = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(note.color.dot.opacity(0.75))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 3) {
                MixedText("已删除一张便签", size: 11.5, color: Theme.ink)
                MixedText(
                    note.displayTitle,
                    size: 9,
                    color: Theme.inkSoft,
                    lineLimit: 1
                )
            }

            Spacer(minLength: 4)

            Button(action: onUndo) {
                MixedText(
                    "撤销",
                    size: 10,
                    weight: .medium,
                    color: Theme.accentDeep
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            hoveringUndo
                                ? Theme.accent.opacity(0.14)
                                : Theme.accent.opacity(0.08)
                        )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hoveringUndo = $0 }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(hoveringClose ? Theme.ink.opacity(0.06) : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringClose = $0 }
        }
        .padding(.horizontal, 17)
        .frame(width: 330, height: 58)
        .background(
            ZStack {
                PaperBackground(color: .cream, cornerRadius: 8)
                PaperTexture(opacity: 0.028)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.18), radius: 16, y: 8)
        .padding(6)
        .frame(width: 342, height: 76)
    }
}
