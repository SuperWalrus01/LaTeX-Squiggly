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
    private static func mathDelimited(buffer: String, terminator: Character) -> TriggerOutcome? {
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

        switch convert(content) {
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

    /// Decides what to do given the buffer and the terminator just typed.
    ///
    /// The terminator is assumed to have been suppressed by the caller, so
    /// `deleteCount` covers only the command source and `insert` carries the
    /// terminator back.
    ///
    /// Two things can fire. A `$...$` span, LaTeX's own inline maths
    /// delimiters, converts whatever is between them. Otherwise the candidate
    /// must start with a backslash.
    ///
    /// Bare `x^2` deliberately does not fire — `2^3` in ordinary prose, or
    /// `a_b` in an identifier, would silently rewrite themselves. Write `$x^2$`
    /// when you mean maths. `\alpha_b` still reports the missing subscript,
    /// because it opens with a command.
    public static func outcome(buffer: String, terminator: Character) -> TriggerOutcome {
        // Explicit maths first: `$x^2$` is unambiguous where bare `x^2` is not.
        if let delimited = mathDelimited(buffer: buffer, terminator: terminator) {
            return delimited
        }
        guard let start = buffer.lastIndex(of: "\\") else { return .none }
        let candidate = String(buffer[start...])

        // A lone backslash, or one already broken by whitespace, is not a
        // pending command.
        guard candidate.count > 1,
              !candidate.contains(where: { $0.isWhitespace }),
              KnownCommands.looksIntentional(candidate)
        else { return .none }

        switch convert(candidate) {
        case .converted(let text):
            return .replace(Replacement(deleteCount: candidate.count,
                                        insert: text + String(terminator),
                                        notice: nil))
        case .fallback(let text, let reason):
            return .replace(Replacement(deleteCount: candidate.count,
                                        insert: text + String(terminator),
                                        notice: reason))
        case .unsupported(let reason):
            return .refuse(source: candidate, reason: reason)
        }
    }
}
