#if DEBUG
import SwiftUI
import UIKit

/// Screens for checking the keyboard's look in the simulator, picked by launch
/// argument. Debug builds only.
///
///   -systemKeyboard   Apple's keyboard, to compare against
///   -keyboardPreview  ours, as the input view of a real text view
///   -renderTab        the Render tab on its own
///
/// PREVIEW_TEXT in the environment pre-fills the text, PREVIEW_PAGE=math
/// opens our keyboard on the math page, and PREVIEW_PANEL=1 opens its large
/// preview of the rendering.
enum DebugScreen: String {
    case systemKeyboard, keyboardPreview, renderTab

    static var requested: DebugScreen? {
        ProcessInfo.processInfo.arguments.lazy
            .compactMap { DebugScreen(rawValue: String($0.dropFirst())) }
            .first
    }
}

struct DebugScreenView: View {
    let screen: DebugScreen

    var body: some View {
        if screen == .renderTab {
            RenderView(latex: ProcessInfo.processInfo.environment["PREVIEW_TEXT"] ?? RenderView.example)
        } else {
            DebugTextView(useOurKeyboard: screen == .keyboardPreview)
                .ignoresSafeArea(.keyboard)
        }
    }
}

private struct DebugTextView: UIViewRepresentable {
    let useOurKeyboard: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .systemFont(ofSize: 20)
        view.text = ProcessInfo.processInfo.environment["PREVIEW_TEXT"] ?? ""
        if useOurKeyboard {
            let host = PreviewHost(textView: view)
            context.coordinator.host = host
            if ProcessInfo.processInfo.environment["PREVIEW_PAGE"] == "math" {
                host.model.page = .math
            }
            if ProcessInfo.processInfo.environment["PREVIEW_PANEL"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    host.model.refresh()
                    host.model.openPreview()
                }
            }
            view.inputView = KeyboardInputView(model: host.model)
        }
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var host: PreviewHost?
    }
}

/// Stands in for the system in the preview: the keyboard model talks to it as
/// it would to a real `UIInputViewController`.
@MainActor
private final class PreviewHost: KeyboardHost {
    let proxy: TextViewProxy
    lazy var model = KeyboardModel(host: self)

    init(textView: UITextView) {
        proxy = TextViewProxy(textView: textView)
    }

    var textDocumentProxy: UITextDocumentProxy { proxy }
    var needsInputModeSwitchKey: Bool { false }
    var hasFullAccess: Bool { true }
    func advanceToNextInputMode() {}
    func requestSupplementaryLexicon(completion: @escaping (UILexicon) -> Void) {}
}

/// A `UITextDocumentProxy` over a text view, so the preview edits real text.
private final class TextViewProxy: NSObject, UITextDocumentProxy {
    private weak var textView: UITextView?

    init(textView: UITextView) {
        self.textView = textView
    }

    private var split: (before: String, after: String) {
        guard let view = textView, let range = view.selectedTextRange else { return ("", "") }
        let before = view.text(in: view.textRange(from: view.beginningOfDocument, to: range.start)!) ?? ""
        let after = view.text(in: view.textRange(from: range.end, to: view.endOfDocument)!) ?? ""
        return (before, after)
    }

    var documentContextBeforeInput: String? { split.before }
    var documentContextAfterInput: String? { split.after }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { textView?.hasText ?? false }

    func insertText(_ text: String) { textView?.insertText(text) }
    func deleteBackward() { textView?.deleteBackward() }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}

    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard let view = textView, let range = view.selectedTextRange,
              let position = view.position(from: range.start, offset: offset) else { return }
        view.selectedTextRange = view.textRange(from: position, to: position)
    }
}
#endif
