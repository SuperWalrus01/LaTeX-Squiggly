import LaTeXUnicode

/// What the app should do when a terminator is typed.
public enum TriggerOutcome: Equatable {
    /// Nothing was pending. Let the keystroke through untouched.
    case none
    /// Replace typed source with Unicode.
    case replace(Replacement)
    /// A real LaTeX attempt that has no honest Unicode form. Leave the text
    /// alone and tell the user why.
    case refuse(source: String, reason: String)
}

public struct Replacement: Equatable {
    /// How many characters of typed source to delete.
    public let deleteCount: Int
    /// What to type in their place, terminator included.
    public let insert: String
    /// Non-nil when the user must be told a fallback happened.
    public let notice: String?

    public init(deleteCount: Int, insert: String, notice: String?) {
        self.deleteCount = deleteCount
        self.insert = insert
        self.notice = notice
    }
}

public enum TriggerDetector {

    /// Keystrokes that complete a command.
    ///
    /// Space and tab only, per the spec's prefix-collision rule. Return is
    /// deliberately excluded: in a chat app it sends the message, and racing a
    /// replacement against a send is a good way to post half a symbol.
    public static let terminators: Set<Character> = [" ", "\t"]


    /// Longest `$...$` span we will consider, so a stray dollar earlier in the
    /// sentence cannot swallow half a line.
    static let maximumDelimitedLength = 48

    /// Characters that make a `$...$` span worth converting.
    ///
    /// Without this, `I have $5$ left` would rewrite itself. Requiring a
    /// backslash, caret or underscore means only spans that actually contain
    /// maths fire, and currency is left alone.
    private static let mathematicalSignals: Set<Character> = ["\\", "^", "_"]

    /// Handles LaTeX's own inline maths delimiters.
    ///
    /// This is how bare scripts become reachable. `x^2` on its own must never
    /// fire — `2^3` in a sentence and `a_b` in an identifier would rewrite
    /// themselves — but `$x^2$` is something nobody types by accident.
    ///
    /// Unlike the backslash path, a failure here is always reported: wrapping
    /// something in `$...$` is a clear statement of intent, so silence would be
    /// the wrong answer.
    ///
    /// - Returns: nil when this is not a delimited span at all, so the caller
    ///   can fall through to the backslash rule.
    private static func mathDelimited(buffer: String,
                                      terminator: Character,
                                      options: ConversionOptions) -> TriggerOutcome? {
        guard buffer.last == "$" else { return nil }
        let beforeClosing = buffer.dropLast()
        guard let opening = beforeClosing.lastIndex(of: "$") else { return nil }

        let content = String(beforeClosing[beforeClosing.index(after: opening)...])
        guard !content.isEmpty,
              content.count <= maximumDelimitedLength,
              content.contains(where: mathematicalSignals.contains)
        else { return nil }

        // Both delimiters are typed source and have to be deleted too.
        let deleteCount = content.count + 2

        switch convert(content, options: options) {
        case .converted(let text):
            return .replace(Replacement(deleteCount: deleteCount,
                                        insert: text + String(terminator),
                                        notice: nil))
        case .fallback(let text, let reason):
            return .replace(Replacement(deleteCount: deleteCount,
                                        insert: text + String(terminator),
                                        notice: reason))
        case .unsupported(let reason):
            return .refuse(source: "$" + content + "$", reason: reason)
        }
    }

    /// Every point at which a candidate could begin, earliest first.
    ///
    /// Whitespace ends a command, so only the run of typing since the last
    /// space can still be pending; within that run, every backslash is a
    /// possible start.
    ///
    /// Earliest first is the whole fix for nested commands. Read from its
    /// *last* backslash, `\\frac{\\alpha}{2}` is `\\alpha}{2}`, which really is
    /// unbalanced, so the user was told their correct LaTeX had a stray brace.
    /// Read from its first, it is the fragment they actually typed.
    private static func candidateStarts(in buffer: String) -> [String] {
        let run: Substring
        if let lastSpace = buffer.lastIndex(where: { $0.isWhitespace }) {
            run = buffer[buffer.index(after: lastSpace)...]
        } else {
            run = buffer[...]
        }
        return run.indices.filter { run[$0] == "\\" }.map { String(run[$0...]) }
    }

    /// Decides what to do given the buffer and the terminator just typed.
    ///
    /// The terminator is assumed to have been suppressed by the caller, so
    /// `deleteCount` covers only the command source and `insert` carries the
    /// terminator back.
    ///
    /// Two things can fire. A `$...$` span, LaTeX's own inline maths
    /// delimiters, converts whatever is between them. Otherwise the candidate
    /// must start with a backslash, and the earliest start that converts wins,
    /// so a command and its arguments are replaced together instead of the
    /// innermost one being picked out of the middle of them.
    ///
    /// Bare `x^2` deliberately does not fire: `2^3` in ordinary prose, or
    /// `a_b` in an identifier, would silently rewrite themselves. Write `$x^2$`
    /// when you mean maths. `\\alpha_b` still reports the missing subscript,
    /// because it opens with a command.
    ///
    /// `options` is passed straight to the engine and read fresh by the caller
    /// on every keystroke, so a switch flipped in the settings window applies to
    /// the next command rather than the next launch.
    public static func outcome(buffer: String,
                               terminator: Character,
                               options: ConversionOptions = .default) -> TriggerOutcome {
        // Explicit maths first: `$x^2$` is unambiguous where bare `x^2` is not.
        if let delimited = mathDelimited(buffer: buffer,
                                         terminator: terminator,
                                         options: options) {
            return delimited
        }

        // Held rather than returned, so a start that cannot convert does not
        // stop a later one that can. `\\foo\\alpha` still converts its alpha.
        var refusal: TriggerOutcome?

        for candidate in candidateStarts(in: buffer) {
            // A lone backslash is not a pending command.
            guard candidate.count > 1, KnownCommands.looksIntentional(candidate) else { continue }

            switch convert(candidate, options: options) {
            case .converted(let text):
                return .replace(Replacement(deleteCount: candidate.count,
                                            insert: text + String(terminator),
                                            notice: nil))
            case .fallback(let text, let reason):
                return .replace(Replacement(deleteCount: candidate.count,
                                            insert: text + String(terminator),
                                            notice: reason))
            case .unsupported(let reason):
                // Say why only when the whole candidate is LaTeX the user
                // plainly meant. A half-recognised run, `\\to\\file` inside a
                // Windows path, stays as quiet as it was before.
                if refusal == nil, KnownCommands.isWhollyIntentional(candidate) {
                    refusal = .refuse(source: candidate, reason: reason)
                }
            }
        }
        return refusal ?? .none
    }
}
