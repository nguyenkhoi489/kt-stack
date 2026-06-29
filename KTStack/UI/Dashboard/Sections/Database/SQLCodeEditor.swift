import AppKit
import KTStackKit
import SwiftUI

struct SQLCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var catalog: SchemaCatalog
    var keywords: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = CompletingTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.catalog = catalog
        textView.keywords = keywords
        textView.highlighter.keywords = Set(keywords.map { $0.uppercased() })
        textView.textStorage?.delegate = textView.highlighter
        textView.string = text
        textView.highlightNow()
        textView.completionController = SQLCompletionController(textView: textView)

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? CompletingTextView else { return }
        textView.catalog = catalog
        textView.keywords = keywords
        textView.highlighter.keywords = Set(keywords.map { $0.uppercased() })
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let clamped = min(selected.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
            textView.highlightNow()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLCodeEditor
        init(_ parent: SQLCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class CompletingTextView: NSTextView {
    var catalog: SchemaCatalog = .empty
    var keywords: [String] = []
    var completionController: SQLCompletionController?
    let highlighter = SQLSyntaxHighlighter()

    func highlightNow() {
        guard let textStorage else { return }
        highlighter.highlight(textStorage)
    }

    override func keyDown(with event: NSEvent) {
        if let controller = completionController, controller.isVisible {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.isEmpty {
                switch event.keyCode {
                case 125: controller.moveDown(); return
                case 126: controller.moveUp(); return
                case 36, 76, 48: controller.acceptSelected(); return
                case 53, 123, 124: controller.hide(); return
                default: break
                }
            }
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        refreshCompletions()
    }

    override func resignFirstResponder() -> Bool {
        completionController?.hide()
        return super.resignFirstResponder()
    }

    private func refreshCompletions() {
        let string = string
        let utf16Caret = selectedRange().location
        let swiftIndex = String.Index(utf16Offset: utf16Caret, in: string)
        let caret = string.distance(from: string.startIndex, to: swiftIndex)
        let items = SQLCompletionEngine.completions(
            text: string, caret: caret, catalog: catalog, keywords: keywords
        )

        let partial = currentPartial(in: string, caret: utf16Caret)
        if items.isEmpty
            || (items.count == 1 && items[0].text.lowercased() == partial.lowercased())
        {
            completionController?.hide()
        } else {
            completionController?.update(items: items, partial: partial)
        }
    }

    private func currentPartial(in string: String, caret: Int) -> String {
        let ns = string as NSString
        var start = caret
        while start > 0 {
            guard let scalar = Unicode.Scalar(ns.character(at: start - 1)),
                  scalar == "_" || CharacterSet.alphanumerics.contains(scalar) else { break }
            start -= 1
        }
        return ns.substring(with: NSRange(location: start, length: caret - start))
    }
}
