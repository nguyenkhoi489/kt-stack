import SwiftUI
import AppKit
import KTStackKit

struct KTVariableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var variableNames: [String]

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: "JetBrainsMono-Medium", size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = NSColor(KTColor.ink)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KTVariableTextField
        private var isCompleting = false

        init(_ parent: KTVariableTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            guard !isCompleting,
                  !parent.variableNames.isEmpty,
                  let editor = field.currentEditor() as? NSTextView else { return }
            let caret = editor.selectedRange().location
            let full = field.stringValue as NSString
            guard caret <= full.length else { return }
            let head = full.substring(to: caret)
            guard let open = head.range(of: "{{", options: .backwards),
                  !head[open.upperBound...].contains("}}") else { return }
            isCompleting = true
            editor.complete(nil)
            isCompleting = false
        }

        func control(_ control: NSControl, textView: NSTextView,
                     completions words: [String], forPartialWordRange charRange: NSRange,
                     indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            let full = textView.string as NSString
            let partial = full.substring(with: charRange).lowercased()
            return parent.variableNames
                .filter { partial.isEmpty || $0.lowercased().hasPrefix(partial) }
                .map { $0 + "}}" }
        }
    }
}
