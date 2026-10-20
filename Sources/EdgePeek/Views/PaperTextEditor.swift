import AppKit
import SwiftUI

/// The note itself is the editor. No source view, no Markdown gutter: Chinese
/// runs in the old Song face, Latin runs in mono, and what is on the paper is
/// exactly what gets saved.
struct PaperTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 18
    var textColor: NSColor = NSColor(Theme.ink)
    var accentColor: NSColor = NSColor(Theme.accentDeep)
    var autoFocus: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.focusRingType = .none
        scrollView.contentView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.insertionPointColor = accentColor
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        applyStyles(to: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
                let length = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: length, length: 0))
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !textView.hasMarkedText() else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(
                NSRange(
                    location: min(selection.location, length),
                    length: min(selection.length, max(0, length - min(selection.location, length)))
                )
            )
            applyStyles(to: textView)
        } else {
            applyStyles(to: textView)
        }
    }

    private func applyStyles(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }
        let length = storage.length
        let selection = textView.selectedRange()

        textView.undoManager?.disableUndoRegistration()
        AppTypography.applyAttributes(
            to: storage,
            size: fontSize,
            textColor: textColor,
            accentColor: accentColor,
            lineSpacing: 6
        )
        textView.undoManager?.enableUndoRegistration()

        if length > 0 {
            let location = min(selection.location, length)
            let attributes = storage.attributes(
                at: max(0, min(location, length - 1)),
                effectiveRange: nil
            )
            textView.typingAttributes = attributes
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            textView.typingAttributes = [
                .font: AppTypography.nsFont(chinese: true, size: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        }
        let safeLocation = min(selection.location, length)
        let safeLength = min(selection.length, max(0, length - safeLocation))
        textView.setSelectedRange(
            NSRange(location: safeLocation, length: safeLength)
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaperTextEditor
        weak var textView: NSTextView?

        init(_ parent: PaperTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            parent.text = textView.string
            parent.applyStyles(to: textView)
        }
    }
}
