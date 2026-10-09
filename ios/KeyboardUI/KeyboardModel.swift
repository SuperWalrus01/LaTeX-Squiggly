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

    /// The one mode switch, in the bar above the keys.
    enum Output: String {
        /// LaTeX mode: nothing converts, and math keys type `\alpha`. For
        /// LaTeX documents, and for long equations to copy as images.
        case latex
        /// Symbols mode: space turns `\alpha` into `α`, and math keys type
        /// `α`. For messages.
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
        /// Selected text with math in it, typeset with its words.
        case selection(String)
        case notice(String)
    }

    @Published var page: KeyboardPage = .letters
    @Published private(set) var shift: Shift = .off
    @Published private(set) var output: Output
    @Published private(set) var strip: Strip = .quick
    @Published private(set) var copied = false
    @Published private(set) var needsGlobe = false
    @Published private(set) var returnLabel: String?
    /// Email addresses and web addresses get their own keys, as in iOS.
    @Published private(set) var field: FieldKind = .text
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
    /// The LaTeX space last converted, so delete straight after undoes it.
    private struct Change {
        let original: String
        let replacement: String
        let terminator: String
    }
    private var lastChange: Change?
    /// LaTeX the user put back after it converted, which space then leaves.
    private var keptLaTeX: String?
    /// Shift turned on by the keyboard at the start of a sentence, rather
    /// than by the user, so it can turn itself off again.
    private var autoShifted = false
    /// Accepting a word types a space after it, which punctuation takes
    /// back, as in iOS: `word` then `,` gives `word,` rather than `word ,`.
    private var autoSpaced = false
    /// The text field being typed in, to notice when it changes.
    private var document: UUID?
    /// The last character typed, until the host app reports its text, which
    /// it does a moment later.
    private var lastTyped: Character?
    /// The keyboard's own settings. A keyboard without Full Access cannot
    /// share the app's, but it keeps its own.
    private let defaults = UserDefaults.standard

    init(host: KeyboardHost) {
        self.host = host
        MathRenderer.teachSymbols()
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

    /// Plain words are being typed, where English spelling odds help: not
    /// maths, and not a command after a backslash.
    var typingWords: Bool {
        let before = self.before
        return !Self.inMath(before) && CommandSuggestions.partialCommand(in: before) == nil
    }

    var hasFullAccess: Bool { host?.hasFullAccess ?? false }

    // MARK: - Keys

    func perform(_ action: KeyAction) {
        notice = nil
        if copied { copied = false }
        if previewOpen { previewOpen = false }
        let change = lastChange
        let spaced = autoSpaced
        // Shift and a page of keys type nothing, so what the last key did
        // still counts after them: `word ` then 123 then `,` is `word,`.
        switch action {
        case .shift, .page: break
        default:
            lastChange = nil
            autoSpaced = false
        }
        lastTyped = nil
        var typed = true

        switch action {
        case .insert(let text):
            let text = shift == .off ? text : text.uppercased()
            if text.count == 1, ".,!?;:".contains(text) {
                // Straight after an accepted word, punctuation goes in place
                // of the space accepting it typed.
                if spaced {
                    proxy?.deleteBackward()
                    proxy?.insertText(text)
                    lastTyped = text.last
                    break
                }
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
            // Space after numbers or symbols goes back to the letters, as in
            // iOS. Not in maths, where `3 + 4` wants the numbers kept.
            if page == .numbers || page == .symbols, !Self.inMath(before) { page = .letters }
        case .backspace:
            if let change, before.hasSuffix(change.replacement + change.terminator) {
                // Delete straight after a conversion puts back the LaTeX,
                // and space then leaves it alone.
                for _ in 0..<(change.replacement + change.terminator).count { proxy?.deleteBackward() }
                proxy?.insertText(change.original)
                keptLaTeX = change.original
            } else {
                proxy?.deleteBackward()
            }
        case .newline:
            proxy?.insertText("\n")
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
                ? "Symbols: \\alpha then space gives α. Maths between $ signs stays LaTeX."
                : "LaTeX mode: nothing converts. Tap LaTeX again to turn it off."
            typed = false
        case .nextKeyboard:
            host?.advanceToNextInputMode()
            typed = false
        }
        refresh(releasingShift: typed)
    }

    /// Replaces the command being typed with the chosen completion.
    func accept(_ suggestion: CommandSuggestions.Suggestion) {
        guard let proxy, let partial = CommandSuggestions.partialCommand(in: before) else { return }
        for _ in 0...partial.count { proxy.deleteBackward() }
        if converts, let glyph = suggestion.glyph {
            proxy.insertText(glyph)
        } else if suggestion.back > 0 {
            proxy.insertText(suggestion.source)
            proxy.adjustTextPosition(byCharacterOffset: -suggestion.back)
        } else {
            // A space ends the command, as accepting a suggestion does in iOS.
            proxy.insertText(suggestion.source + " ")
        }
        refresh(releasingShift: true)
    }

    /// Puts a word from the bar in place of the one being typed. Words are
    /// only ever changed this way, when the user taps one: nothing is
    /// corrected on its own.
    func accept(word: String) {
        guard let proxy, let typed = WordCorrector.currentWord(in: before) else { return }
        for _ in 0..<typed.count { proxy.deleteBackward() }
        proxy.insertText(word + " ")
        lastTyped = " "
        lastPlainSpace = Date()
        autoSpaced = true
        refresh(releasingShift: true)
    }

    func setCursorMode(_ on: Bool) {
        cursorMode = on
        if !on { refresh() }
    }

    /// The host app's text or cursor changed. Its context is current again.
    func textChanged() {
        lastTyped = nil
        refresh()
        updateAutoShift()
    }

    func openPreview() {
        if rendering() != nil { previewOpen = true }
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
        refresh(releasingShift: true)
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
        switch rendering() {
        case nil:
            break
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

    /// What Copy and the large preview make: the selection if there is one,
    /// else the equation at the cursor, in the chosen size and colours.
    func rendering() -> Result<UIImage, MathRenderer.Failure>? {
        let size = renderStyle.size.fontSize, dark = renderStyle.dark
        switch renderTarget() {
        case .selection(let text): return MathRenderer.passage(text, fontSize: size, dark: dark)
        case .math(let latex): return MathRenderer.image(latex: latex, fontSize: size, dark: dark)
        default: return nil
        }
    }

    /// Selected text with math in it, or else the math at the cursor if it
    /// typesets.
    private func renderTarget() -> Strip? {
        if let selected = proxy?.selectedText, Self.containsMath(selected) {
            return .selection(selected)
        }
        if let source = MathSource.around(before: before, after: after), Self.looksLikeMath(source),
           Self.parses(source) {
            return .math(latex: source)
        }
        return nil
    }

    // MARK: - State

    /// Called after every key and whenever the host app's text changes.
    /// Only what changed is published, so the keys redraw once per press.
    func refresh(releasingShift: Bool = false) {
        if let id = proxy?.documentIdentifier, id != document {
            let first = document == nil
            document = id
            newField(first: first)
        }
        let globe = host?.needsInputModeSwitchKey ?? false
        if needsGlobe != globe { needsGlobe = globe }
        let label = Self.label(for: proxy?.returnKeyType ?? .default)
        if returnLabel != label { returnLabel = label }
        let kind = FieldKind(proxy?.keyboardType ?? .default)
        if field != kind { field = kind }
        if releasingShift {
            releaseShift()
            updateAutoShift()
        }
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

        if let target = renderTarget() { return target }
        // A finished `$...$` that still will not typeset says why, rather
        // than the bar staying quietly empty. Finished means the cursor is
        // past its closing `$`; while the user is still typing inside one,
        // half an equation is bound not to typeset.
        if before.trimmingCharacters(in: .whitespaces).hasSuffix("$"),
           MathSource.openSpan(in: before) == nil,
           let source = MathSource.around(before: before, after: after),
           source.count > 2, source.hasPrefix("$"), source.hasSuffix("$"),
           let problem = Self.parseError(source) {
            return .notice("Can't render this: \(problem)")
        }

        if wordsWanted, !Self.inMath(before), let word = WordCorrector.currentWord(in: before) {
            return .words(words.offer(for: word))
        }
        return .quick
    }

    /// Spelling suggestions, unless the text field turns them off, as code
    /// editors, address bars and email fields do.
    private var wordsWanted: Bool {
        guard let proxy, proxy.autocorrectionType != .no else { return false }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .webSearch, .twitter: return false
        default: return true
        }
    }

    /// A different text field: what was typed in the last one no longer
    /// applies, and the keys start where the field asks, numbers for a
    /// numbers field and letters otherwise. The first field keeps the page
    /// the keyboard opened on.
    private func newField(first: Bool) {
        lastChange = nil
        keptLaTeX = nil
        autoSpaced = false
        notice = nil
        if previewOpen { previewOpen = false }
        if proxy?.keyboardType == .numbersAndPunctuation {
            page = .numbers
        } else if !first, page != .letters {
            page = .letters
        }
        if shift != .off { shift = .off }
        autoShifted = false
        updateAutoShift()
    }

    private func show(_ message: String) {
        notice = message
        strip = .notice(message)
    }

    // MARK: - Typing behaviour

    /// Symbols mode converts, except in fields that only take plain ASCII,
    /// like some usernames, where only LaTeX can go.
    private var converts: Bool {
        output == .unicode && proxy?.keyboardType != .asciiCapable
    }

    private func insertMath(_ source: String) {
        if converts, case .converted(let glyph) = convert(source) {
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
        // Inside `$...$`, space is only a space. The LaTeX stays as typed, so
        // a long equation can be finished and copied as an image; it converts
        // when space follows the closing `$`. Likewise LaTeX put back by
        // delete after it converted.
        if MathSource.openSpan(in: before) != nil || keptLaTeX.map(before.hasSuffix) == true {
            keptLaTeX = nil
            proxy.insertText(" ")
            lastPlainSpace = .distantPast
            return
        }
        // Only symbols mode converts, and never math between `$` signs, which
        // is for copying as an image.
        let converting = converts && !before.hasSuffix("$")
        switch converting ? TriggerDetector.outcome(buffer: before, terminator: " ") : .none {
        case .replace(let r):
            let source = String(before.suffix(r.deleteCount))
            for _ in 0..<r.deleteCount { proxy.deleteBackward() }
            proxy.insertText(r.insert)
            lastChange = Change(original: source, replacement: String(r.insert.dropLast()), terminator: " ")
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
        autoShifted = false
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
        autoShifted = false
    }

    /// Capitals where the field asks for them, as the system keyboard does:
    /// at the start of a sentence for most fields, of every word for names,
    /// or throughout. Shift the keyboard turned on turns off again when the
    /// cursor leaves the start of a sentence; shift the user set is theirs.
    private func updateAutoShift() {
        guard shift != .locked else { return }
        let wanted = wantsCapital()
        if wanted, shift == .off {
            shift = .on
            autoShifted = true
        } else if !wanted, shift == .on, autoShifted {
            shift = .off
            autoShifted = false
        }
    }

    private func wantsCapital() -> Bool {
        guard let proxy else { return false }
        let style = proxy.autocapitalizationType ?? .sentences
        if style == .allCharacters { return true }
        // Straight after a letter, never, whatever the context still says:
        // the host app reports the text a moment after it changes.
        if let typed = lastTyped, !typed.isWhitespace { return false }
        var before = self.before
        if let typed = lastTyped, before.last?.isWhitespace != true { before.append(typed) }
        guard !Self.inMath(before) else { return false }
        switch style {
        case .words: return before.last.map(\.isWhitespace) ?? true
        case .sentences: return Self.startsSentence(before)
        default: return false
        }
    }

    /// The start of the text, of a line, or of a sentence after `.`, `!` or
    /// `?` and a space, with any closing quote or bracket between.
    static func startsSentence(_ before: String) -> Bool {
        guard let last = before.last else { return true }
        if last.isNewline { return true }
        guard last.isWhitespace else { return false }
        let text = before.reversed().drop(while: { $0.isWhitespace && !$0.isNewline })
            .drop(while: { "\"')]”’".contains($0) })
        guard let end = text.first else { return true }
        return ".!?".contains(end) || end.isNewline
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

    /// Worth typesetting: a `$...$` span, a command, scripts, or symbols
    /// space already converted, like `α + β`. Plain words are left alone.
    private static func looksLikeMath(_ source: String) -> Bool {
        if MathRenderer.hasSymbols(source) { return true }
        if source.count > 2, source.hasPrefix("$"), source.hasSuffix("$") { return true }
        if source.contains(where: { $0 == "^" || $0 == "_" }) { return true }
        guard let slash = source.firstIndex(of: "\\") else { return false }
        let next = source.index(after: slash)
        return next < source.endIndex && source[next].isLetter
    }

    /// Inside an unfinished `$...$` or an unclosed brace.
    static func inMath(_ before: String) -> Bool {
        MathSource.openSpan(in: before) != nil || MathSource.openBraces(in: before) > 0
    }

    /// Text worth typesetting from a selection: math anywhere in it.
    private static func containsMath(_ text: String) -> Bool {
        text.filter { $0 == "$" }.count >= 2 || text.contains("\\(") || text.contains("\\[")
            || looksLikeMath(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parses(_ source: String) -> Bool {
        !MathRenderer.restoringLaTeX(MathRenderer.stripDelimiters(source)).isEmpty && parseError(source) == nil
    }

    /// What SwiftMath says is wrong with `source`, like `Invalid command \foo`.
    private static func parseError(_ source: String) -> String? {
        var error: NSError?
        let latex = MathRenderer.restoringLaTeX(MathRenderer.stripDelimiters(source))
        let list = MTMathListBuilder.build(fromString: latex, error: &error)
        if let error { return error.localizedDescription }
        return list == nil ? "it is not valid LaTeX" : nil
    }
}

extension FieldKind {
    init(_ type: UIKeyboardType) {
        switch type {
        case .emailAddress: self = .email
        case .URL, .webSearch: self = .web
        default: self = .text
        }
    }
}
