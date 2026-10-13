#if DEBUG
import SwiftUI
import UIKit

/// Screens for checking the keyboard's look in the simulator, picked by launch
/// argument. Debug builds only.
///
///   -systemKeyboard   Apple's keyboard, to compare against
///   -keyboardPreview  ours, as the input view of a real text view
///   -renderTab        the Render tab on its own
///   -shareSheet       the share sheet's screen, with PREVIEW_TEXT shared
///   -messagesDrawer   the Messages app in the drawer, with -recent '("x^2")'
///   -messagesEditor   the Messages app opened up to write an equation
///
/// PREVIEW_TEXT in the environment pre-fills the text, PREVIEW_PAGE=math or
/// emoji opens our keyboard on that page, and PREVIEW_PANEL=1 opens its large
/// preview of the rendering, and PREVIEW_SELECT=1 selects all the text.
enum DebugScreen: String {
    case systemKeyboard, keyboardPreview, renderTab, shareSheet, messagesDrawer, messagesEditor

    static var requested: DebugScreen? {
        ProcessInfo.processInfo.arguments.lazy
            .compactMap { DebugScreen(rawValue: String($0.dropFirst())) }
            .first
    }
}

struct DebugScreenView: View {
    let screen: DebugScreen

    var body: some View {
        let text = ProcessInfo.processInfo.environment["PREVIEW_TEXT"]
        switch screen {
        case .renderTab:
            RenderView(latex: text ?? RenderView.example)
        case .shareSheet:
            ShareSheet(source: text ?? RenderView.example) {}
        case .messagesDrawer, .messagesEditor:
            MessagesPreview(expanded: screen == .messagesEditor, source: text ?? "")
        case .systemKeyboard, .keyboardPreview:
            DebugTextView(useOurKeyboard: screen == .keyboardPreview)
                .ignoresSafeArea(.keyboard)
        }
    }
}

/// The Messages app's view at the height Messages gives it, compact in the
/// drawer or opened up.
private struct MessagesPreview: View {
    @StateObject private var state = MessagesState()
    let expanded: Bool
    let source: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            MessagesRoot(state: state, expand: {}, insert: { _, _ in })
                .frame(height: expanded ? nil : 260)
        }
        .onAppear {
            state.expanded = expanded
            state.source = source
        }
    }
}

private struct DebugTextView: UIViewRepresentable {
    let useOurKeyboard: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .systemFont(ofSize: 20)
        // Side margins like Notes'. The top and bottom stay as they were, so
        // the user guide's crops still fall between lines.
        view.textContainerInset = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        view.text = ProcessInfo.processInfo.environment["PREVIEW_TEXT"] ?? ""
        if useOurKeyboard {
            let host = PreviewHost(textView: view)
            context.coordinator.host = host
            switch ProcessInfo.processInfo.environment["PREVIEW_PAGE"] {
            case "math": host.model.page = .math
            case "emoji": host.model.page = .emoji
            default: break
            }
            if ProcessInfo.processInfo.environment["PREVIEW_PANEL"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    host.model.refresh()
                    host.model.openPreview()
                }
            }
            view.inputView = KeyboardInputView(model: host.model)
        }
        DispatchQueue.main.async {
            view.becomeFirstResponder()
            if ProcessInfo.processInfo.environment["PREVIEW_SELECT"] == "1" {
                view.selectAll(nil)
                (view.inputView as? KeyboardInputView)?.hosting.rootView.model.refresh()
            }
        }
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
    func handleInputModeList(from view: UIView, with event: UIEvent) {}
    func requestSupplementaryLexicon(completion: @escaping (UILexicon) -> Void) {}
}

/// A `UITextDocumentProxy` over a text view, so the preview edits real text.
private final class TextViewProxy: NSObject, UITextDocumentProxy {
    private weak var textView: UITextView?
    /// One field, so the keyboard does not take every key for a new one.
    let documentIdentifier = UUID()

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
    var selectedText: String? {
        guard let view = textView, let range = view.selectedTextRange, !range.isEmpty else { return nil }
        return view.text(in: range)
    }
    var documentInputMode: UITextInputMode? { nil }
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
