import Foundation
import InputTracking
import LaTeXUnicode
import SwiftMath
import UIKit

/// Everything a key press does, kept out of the views.
///
/// Typing reads the host app's text through `textDocumentProxy` rather than
/// keeping its own buffer, because the user can move the cursor or paste at
/// any time and the proxy is the only thing that knows.
@MainActor
final class KeyboardModel: ObservableObject {

    enum Output: String {
        /// Math keys type `\alpha`, for LaTeX documents.
        case latex
        /// Math keys type `α`, for messages.
        case unicode
    }

    enum Shift {
        case off, on, locked
    }

    /// How a rendered equation looks, kept between sessions.
    struct RenderStyle: Equatable {
        enum Size: String, CaseIterable {
            case small, medium, large
            var fontSize: CGFloat { [.small: 20, .medium: 28, .large: 40][self]! }
        }
        var size: Size = .medium
        var dark = false
    }

    /// What the bar above the keys shows, in the place iOS shows predictions.
    enum Strip: Equatable {
        /// Buttons for `$…$`, braces and scripts, when nothing else applies.
        case quick
        /// Completions for the command being typed.
        case suggestions([CommandSuggestions.Suggestion])
        /// Spellings and completions for the plain word being typed.
        case words(WordCorrector.Offer)
        /// The LaTeX before the cursor, typeset.
        case math(latex: String)
        case notice(String)
    }

    @Published var page: KeyboardPage = .letters
    @Published private(set) var shift: Shift = .off
    @Published private(set) var output: Output
    @Published private(set) var strip: Strip = .quick
    @Published private(set) var copied = false
    @Published private(set) var needsGlobe = false
    @Published private(set) var returnLabel: String?
    /// True while space is being used as a trackpad.
    @Published private(set) var cursorMode = false
    /// The large preview of the rendering, in place of the keys.
    @Published private(set) var previewOpen = false
    @Published private(set) var renderStyle: RenderStyle

    /// Fingers on the keys, published separately so a press redraws only keys.
    let presses = KeyPresses()

    private weak var host: KeyboardHost?
    private var proxy: UITextDocumentProxy? { host?.textDocumentProxy }
    private var before: String { proxy?.documentContextBeforeInput ?? "" }
    private var after: String { proxy?.documentContextAfterInput ?? "" }
    private var notice: String?
    private var lastShiftTap = Date.distantPast
    private var lastPlainSpace = Date.distantPast
    private let words = WordCorrector()
    /// The last correction space made, so delete straight after undoes it.
    private var lastCorrection: (original: String, corrected: String, terminator: String)?
    /// The last character typed, until the host app reports its text, which
    /// it does a moment later.
    private var lastTyped: Character?
    /// The keyboard's own settings. A keyboard without Full Access cannot
    /// share the app's, but it keeps its own.
    private let defaults = UserDefaults.standard

    init(host: KeyboardHost) {
        self.host = host
        output = Output(rawValue: defaults.string(forKey: "output") ?? "") ?? .unicode
        renderStyle = RenderStyle(
            size: RenderStyle.Size(rawValue: defaults.string(forKey: "renderSize") ?? "") ?? .medium,
            dark: defaults.bool(forKey: "renderDark"))
        host.requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async { self?.words.use(lexicon) }
        }
    }

    /// The character before the cursor, for guessing which key was meant.
    var previousCharacter: Character? { lastTyped ?? before.last }

    var hasFullAccess: Bool { host?.hasFullAccess ?? false }

    // MARK: - Keys

    func perform(_ action: KeyAction) {
        notice = nil
        if copied { copied = false }
        if previewOpen { previewOpen = false }
        let correction = lastCorrection
        lastCorrection = nil
        lastTyped = nil
        var typed = true

        switch action {
        case .insert(let text):
            let text = shift == .off ? text : text.uppercased()
            // Punctuation ends a word, so it corrects it first, as space does.
            if text.count == 1, ".,!?;:".contains(text), autocorrect(adding: text) {
                break
            }
            proxy?.insertText(text)
            lastTyped = text.last
            // An apostrophe goes back to the letters, for "don't", as in iOS.
            if text == "'", page == .numbers || page == .symbols { page = .letters }
        case .math(let source):
            insertMath(source)
        case .template(let source, let back):
            proxy?.insertText(source)
            proxy?.adjustTextPosition(byCharacterOffset: -back)
        case .space:
            space()
            lastTyped = " "
        case .backspace:
            if let correction, before.hasSuffix(correction.corrected + correction.terminator) {
                // Delete straight after a correction puts the word back.
                for _ in 0..<(correction.corrected + correction.terminator).count { proxy?.deleteBackward() }
                proxy?.insertText(correction.original)
                words.reject(correction.original)
            } else {
                proxy?.deleteBackward()
            }
        case .newline:
            if !autocorrect(adding: "\n") { proxy?.insertText("\n") }
        case .shift:
            tapShift()
            refresh()
            return
        case .page(let next):
            page = next
            typed = false
        case .toggleOutput:
            output = output == .unicode ? .latex : .unicode
            defaults.set(output.rawValue, forKey: "output")
            notice = output == .unicode
                ? "Symbol keys type symbols, like α."
                : "Symbol keys type LaTeX, like \\alpha."
            typed = false
        case .nextKeyboard:
            host?.advanceToNextInputMode()
            typed = false
        }
        refresh(releasingShift: typed, autoShift: typed)
    }

    /// Replaces the command being typed with the chosen completion.
    func accept(_ suggestion: CommandSuggestions.Suggestion) {
        guard let proxy, let partial = CommandSuggestions.partialCommand(in: before) else { return }
        for _ in 0...partial.count { proxy.deleteBackward() }
        if output == .unicode, let glyph = suggestion.glyph {
            proxy.insertText(glyph)
        } else if suggestion.back > 0 {
            proxy.insertText(suggestion.source)
            proxy.adjustTextPosition(byCharacterOffset: -suggestion.back)
        } else {
            // A space ends the command, as accepting a suggestion does in iOS.
            proxy.insertText(suggestion.source + " ")
        }
        refresh(releasingShift: true, autoShift: true)
    }

    /// Puts a word from the bar in place of the one being typed. Choosing
    /// the word as typed keeps it, and space stops correcting it.
    func accept(word: String, keepingTyped: Bool) {
        guard let proxy, let typed = WordCorrector.currentWord(in: before) else { return }
        if keepingTyped { words.reject(typed) }
        for _ in 0..<typed.count { proxy.deleteBackward() }
        proxy.insertText(word + " ")
        lastTyped = " "
        lastPlainSpace = Date()
        refresh(releasingShift: true, autoShift: true)
    }

    func setCursorMode(_ on: Bool) {
        cursorMode = on
        if !on { refresh(autoShift: true) }
    }

    /// The host app's text or cursor changed. Its context is current again.
    func textChanged() {
        lastTyped = nil
        refresh(autoShift: true)
    }

    func openPreview() {
        if case .math = strip { previewOpen = true }
    }

    func closePreview() {
        previewOpen = false
    }

    func setRenderStyle(_ style: RenderStyle) {
        renderStyle = style
        defaults.set(style.size.rawValue, forKey: "renderSize")
        defaults.set(style.dark, forKey: "renderDark")
    }

    /// Delete held down: the spaces before the cursor and the word before them.
    func deleteWordBackward() {
        guard let proxy else { return }
        let before = self.before
        let word = before.reversed().drop(while: \.isWhitespace).prefix(while: { !$0.isWhitespace })
        let spaces = before.reversed().prefix(while: \.isWhitespace)
        for _ in 0..<max(1, spaces.count + word.count) { proxy.deleteBackward() }
        refresh(releasingShift: true, autoShift: true)
    }

    func moveCursor(by characters: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: characters)
    }

    /// Typesets the LaTeX before the cursor and puts the image on the
    /// clipboard. A keyboard can only insert text, so the user pastes it.
    func copyRendering() {
        guard hasFullAccess else {
            show("Turn on Allow Full Access for LaTeX Squiggly in Settings to copy images.")
            return
        }
        guard let source = MathSource.around(before: before, after: after) else { return }
        switch MathRenderer.image(latex: source, fontSize: renderStyle.size.fontSize, dark: renderStyle.dark) {
        case .success(let image):
            MathRenderer.copy(image)
            copied = true
            show("Copied. Touch and hold the text box, then tap Paste.")
        case .failure(.empty):
            break
        case .failure(.parse(let message)):
            show("Could not render: \(message)")
        }
    }

    // MARK: - State

    /// Called after every key and whenever the host app's text changes.
    /// Only what changed is published, so the keys redraw once per press.
    func refresh(releasingShift: Bool = false, autoShift: Bool = false) {
        let globe = host?.needsInputModeSwitchKey ?? false
        if needsGlobe != globe { needsGlobe = globe }
        let label = Self.label(for: proxy?.returnKeyType ?? .default)
        if returnLabel != label { returnLabel = label }
        if releasingShift { releaseShift() }
        if autoShift { capitaliseIfNeeded() }
        let strip = currentStrip()
        if self.strip != strip { self.strip = strip }
    }

    private func currentStrip() -> Strip {
        if let notice { return .notice(notice) }
        let before = self.before

        if let partial = CommandSuggestions.partialCommand(in: before) {
            let found = CommandSuggestions.suggestions(for: partial)
            // A finished command with nothing longer to offer shows its rendering.
            if !(found.isEmpty || found.count == 1 && found[0].command == partial) {
                return .suggestions(found)
            }
        }

        if let source = MathSource.around(before: before, after: after), Self.looksLikeMath(source),
           Self.parses(source) {
            return .math(latex: source)
        }

        if wordsWanted, !Self.inMath(before), let word = WordCorrector.currentWord(in: before) {
            return .words(words.offer(for: word))
        }
        return .quick
    }

    /// Spelling help, unless the text field turns it off, as code editors,
    /// address bars and email fields do.
    private var wordsWanted: Bool {
        guard let proxy, proxy.autocorrectionType != .no else { return false }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .webSearch, .twitter: return false
        default: return true
        }
    }

    /// Replaces a misspelled word before the cursor with its correction, then
    /// types `terminator`. False, and nothing typed, if there was nothing to do.
    private func autocorrect(adding terminator: String) -> Bool {
        let before = self.before
        guard wordsWanted, let proxy, !Self.inMath(before),
              let word = WordCorrector.currentWord(in: before),
              let fixed = words.correction(for: word), fixed != word else { return false }
        for _ in 0..<word.count { proxy.deleteBackward() }
        proxy.insertText(fixed + terminator)
        lastCorrection = (word, fixed, terminator)
        return true
    }

    private func show(_ message: String) {
        notice = message
        strip = .notice(message)
    }

    // MARK: - Typing behaviour

    private func insertMath(_ source: String) {
        if output == .unicode, case .converted(let glyph) = convert(source) {
            proxy?.insertText(glyph)
        } else {
            // A trailing space ends the command, so `\alpha` then `x` does not
            // become the unknown `\alphax`.
            proxy?.insertText(source + " ")
        }
    }

    /// Space converts trailing LaTeX the way the Mac app does: the same
    /// engine, the same rules about when to stay quiet. Otherwise it behaves
    /// like the system's, double space and all.
    private func space() {
        guard let proxy else { return }
        let before = self.before

        // Inside a template's braces, space steps out of them instead, and
        // into the next pair if there is one: `\frac{a|}{}` to `\frac{a}{|}`.
        // The new position is worked out from the text already read, because
        // the proxy's context can lag behind a cursor move.
        let after = self.after
        if after.hasPrefix("}"), MathSource.openBraces(in: before) > 0 {
            proxy.adjustTextPosition(byCharacterOffset: after.hasPrefix("}{") ? 2 : 1)
            lastPlainSpace = .distantPast
            return
        }
        if autocorrect(adding: " ") {
            // Double space still types a full stop after a corrected word.
            lastPlainSpace = Date()
            return
        }
        switch TriggerDetector.outcome(buffer: before, terminator: " ") {
        case .replace(let r):
            for _ in 0..<r.deleteCount { proxy.deleteBackward() }
            proxy.insertText(r.insert)
            notice = r.notice
            lastPlainSpace = .distantPast
            return
        case .refuse(_, let reason):
            notice = reason
        case .none:
            break
        }

        // Double space types a full stop, after a word, quickly, as in iOS.
        let quick = Date().timeIntervalSince(lastPlainSpace) < 0.4
        let afterWord = before.hasSuffix(" ")
            && before.dropLast().last.map { $0.isLetter || $0.isNumber } == true
        if quick && afterWord {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastPlainSpace = .distantPast
        } else {
            proxy.insertText(" ")
            lastPlainSpace = Date()
        }
    }

    /// Tap for one capital, double-tap for caps lock, tap again to release.
    private func tapShift() {
        let now = Date()
        switch shift {
        case .locked:
            shift = .off
        case .on where now.timeIntervalSince(lastShiftTap) < 0.3:
            shift = .locked
        case .on:
            shift = .off
        case .off:
            shift = .on
        }
        lastShiftTap = now
    }

    /// Shift lasts for one character unless locked.
    private func releaseShift() {
        if shift == .on { shift = .off }
    }

    /// Turns shift on where the text field asks for a capital, as the system
    /// keyboard does: at the start of a sentence in Messages, never in a code
    /// editor. Never inside math either, because LaTeX is case-sensitive and
    /// `\Alpha` is not `\alpha`.
    private func capitaliseIfNeeded() {
        guard shift == .off, let proxy else { return }
        let before = self.before
        let wanted: Bool
        switch proxy.autocapitalizationType ?? .sentences {
        case .allCharacters: wanted = true
        case .words: wanted = before.last.map(\.isWhitespace) ?? true
        case .sentences: wanted = Self.startsSentence(before)
        default: wanted = false
        }
        if wanted && !Self.inMath(before) { shift = .on }
    }

    // MARK: - Helpers

    /// What the return key says. `nil` means the plain return arrow.
    private static func label(for type: UIReturnKeyType) -> String? {
        switch type {
        case .go: return "go"
        case .google, .yahoo, .search: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .send: return "send"
        case .done: return "done"
        case .emergencyCall: return "Emergency"
        case .continue: return "continue"
        default: return nil
        }
    }

    /// Worth typesetting: a `$...$` span, a command, or scripts. Plain words
    /// are left to look like words.
    private static func looksLikeMath(_ source: String) -> Bool {
        if source.count > 2, source.hasPrefix("$"), source.hasSuffix("$") { return true }
        if source.contains(where: { $0 == "^" || $0 == "_" }) { return true }
        guard let slash = source.firstIndex(of: "\\") else { return false }
        let next = source.index(after: slash)
        return next < source.endIndex && source[next].isLetter
    }

    /// The start of the text, a new line, or a space after `.`, `!` or `?`.
    static func startsSentence(_ before: String) -> Bool {
        if before.last?.isNewline ?? true { return true }
        let text = before.reversed().drop(while: { $0 == " " })
        guard let last = text.first else { return true }
        return text.count < before.count && ".!?".contains(last)
    }

    /// Inside an unclosed `$` or an unclosed brace.
    static func inMath(_ before: String) -> Bool {
        before.filter { $0 == "$" }.count % 2 == 1 || MathSource.openBraces(in: before) > 0
    }

    private static func parses(_ source: String) -> Bool {
        var error: NSError?
        let latex = MathRenderer.stripDelimiters(source)
        return !latex.isEmpty && MTMathListBuilder.build(fromString: latex, error: &error) != nil && error == nil
    }
}
