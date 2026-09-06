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

    /// Decides what to do given the buffer and the terminator just typed.
    ///
    /// The terminator is assumed to have been suppressed by the caller, so
    /// `deleteCount` covers only the command source and `insert` carries the
    /// terminator back.
    ///
    /// A candidate must start with a backslash. Bare `x^2` therefore does not
    /// fire — otherwise `2^3` in ordinary prose, or `a_b` in an identifier,
    /// would silently rewrite themselves. `\alpha_b` still reports the missing
    /// subscript, because it opens with a command.
    public static func outcome(buffer: String, terminator: Character) -> TriggerOutcome {
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
