#if os(iOS)
import SwiftUI
import UIKit

/// Native text selection, undo, dictation and formatting for the writing page.
struct RichNoteEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var formattedText: Data?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        view.adjustsFontForContentSizeCategory = true
        view.allowsEditingTextAttributes = true
        view.delegate = context.coordinator
        view.accessibilityLabel = "Your rewritten note"
        view.attributedText = NoteTextDocument.load(text: text, data: formattedText)
        view.typingAttributes = NoteTextDocument.bodyAttributes
        context.coordinator.textView = view
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(title: "Body", style: .plain, target: context.coordinator, action: #selector(Coordinator.body)),
            UIBarButtonItem(title: "Heading", style: .plain, target: context.coordinator, action: #selector(Coordinator.heading)),
            UIBarButtonItem(image: UIImage(systemName: "bold"), style: .plain, target: context.coordinator, action: #selector(Coordinator.bold)),
            UIBarButtonItem(image: UIImage(systemName: "italic"), style: .plain, target: context.coordinator, action: #selector(Coordinator.italic)),
            UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: context.coordinator, action: #selector(Coordinator.bullet)),
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .prominent, target: context.coordinator, action: #selector(Coordinator.done))
        ]
        toolbar.items?[2].accessibilityLabel = "Bold"
        toolbar.items?[3].accessibilityLabel = "Italic"
        toolbar.items?[4].accessibilityLabel = "Bullet list"
        toolbar.sizeToFit()
        view.inputAccessoryView = toolbar
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Never reset attributed text during typing: doing so drops selection and undo.
        if view.text != text {
            view.attributedText = NoteTextDocument.load(text: text, data: formattedText)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichNoteEditor
        weak var textView: UITextView?
        init(_ parent: RichNoteEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) { persist(textView) }

        private func persist(_ view: UITextView) {
            parent.text = view.text
            parent.formattedText = try? view.attributedText.data(
                from: NSRange(location: 0, length: view.attributedText.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }

        private func changeFont(_ transform: (UIFont) -> UIFont, paragraph: Bool = false) {
            guard let view = textView else { return }
            var range = view.selectedRange
            if paragraph, view.textStorage.length > 0 {
                range = (view.text as NSString).paragraphRange(for: range)
            }
            if range.length == 0 {
                var attributes = view.typingAttributes
                attributes[.font] = transform(attributes[.font] as? UIFont ?? NoteTextDocument.bodyFont)
                view.typingAttributes = attributes
                return
            }
            let previous = NSAttributedString(attributedString: view.attributedText)
            view.undoManager?.registerUndo(withTarget: self) { target in
                guard let view = target.textView else { return }
                view.attributedText = previous
                target.persist(view)
            }
            view.textStorage.beginEditing()
            view.textStorage.enumerateAttribute(.font, in: range) { value, span, _ in
                view.textStorage.addAttribute(.font, value: transform(value as? UIFont ?? NoteTextDocument.bodyFont), range: span)
            }
            view.textStorage.endEditing()
            persist(view)
        }

        @objc func body() { changeFont({ _ in NoteTextDocument.bodyFont }, paragraph: true) }
        @objc func heading() { changeFont({ _ in UIFont.preferredFont(forTextStyle: .title2) }, paragraph: true) }
        @objc func bold() { toggle(.traitBold) }
        @objc func italic() { toggle(.traitItalic) }
        private func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
            guard let view = textView else { return }
            let current = view.typingAttributes[.font] as? UIFont ?? NoteTextDocument.bodyFont
            let remove = current.fontDescriptor.symbolicTraits.contains(trait)
            changeFont { font in
                var traits = font.fontDescriptor.symbolicTraits
                if remove { traits.remove(trait) } else { traits.insert(trait) }
                return font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
            }
        }
        @objc func bullet() {
            guard let view = textView else { return }
            let previous = NSAttributedString(attributedString: view.attributedText)
            view.undoManager?.registerUndo(withTarget: self) { target in
                guard let view = target.textView else { return }
                view.attributedText = previous
                target.persist(view)
            }
            let range = (view.text as NSString).paragraphRange(for: view.selectedRange)
            let paragraphs = (view.text as NSString).substring(with: range).components(separatedBy: "\n")
            let remove = paragraphs.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix("• ") }
            // Apply prefixes in reverse to preserve formatting and selected ranges.
            var offset = range.location
            var positions: [(Int, String)] = []
            for line in paragraphs {
                if !line.isEmpty { positions.append((offset, line)) }
                offset += (line as NSString).length + 1
            }
            for (position, line) in positions.reversed() {
                if remove, line.hasPrefix("• ") {
                    view.textStorage.deleteCharacters(in: NSRange(location: position, length: 2))
                } else if !remove, !line.hasPrefix("• ") {
                    view.textStorage.insert(NSAttributedString(string: "• ", attributes: NoteTextDocument.bodyAttributes), at: position)
                }
            }
            if positions.isEmpty { view.insertText("• ") }
            persist(view)
        }
        @objc func done() { textView?.resignFirstResponder() }
    }
}

struct RichNoteBody: UIViewRepresentable {
    let text: String
    let formattedText: Data?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.dataDetectorTypes = .link
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = NoteTextDocument.load(text: text, data: formattedText)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

private enum NoteTextDocument {
    static var bodyFont: UIFont {
        let descriptor = UIFont.preferredFont(forTextStyle: .body).fontDescriptor
        return UIFont(descriptor: descriptor.withDesign(.serif) ?? descriptor, size: 0)
    }
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 10
        return [.font: bodyFont, .foregroundColor: UIColor(OneFeedTheme.ink), .paragraphStyle: paragraph]
    }
    static func load(text: String, data: Data?) -> NSAttributedString {
        if let data,
           let stored = try? NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           stored.string == text {
            // RTF colors are fixed; resolve the app's current light/dark ink on display.
            stored.addAttribute(.foregroundColor, value: UIColor(OneFeedTheme.ink), range: NSRange(location: 0, length: stored.length))
            return stored
        }
        return NSAttributedString(string: text, attributes: bodyAttributes)
    }
}
#endif
