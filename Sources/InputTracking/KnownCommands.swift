import LaTeXUnicode

/// Decides whether a candidate is a LaTeX attempt at all.
///
/// This is what keeps the app quiet in normal typing. A Windows path like
/// `C:\Users ` reaches the trigger check with a backslash in it, but `Users` is
/// not a command anyone defined, so nothing fires and nothing is reported. The
/// user is only ever told about a failure they plausibly meant to cause.
public enum KnownCommands {

    /// Commands the converter handles structurally rather than through a table.
    static let structural: Set<String> = [
        "frac", "dfrac", "tfrac", "sqrt", "binom", "dbinom", "tbinom",
        "text", "textrm", "mathrm", "operatorname", "mathbb",
        "left", "right", "begin", "end",
    ]

    /// The command name at the start of `candidate`, which must begin with a
    /// backslash. `\int_5^6` gives `int`.
    public static func leadingCommandName(of candidate: String) -> String? {
        guard candidate.first == "\\" else { return nil }
        var name = ""
        for character in candidate.dropFirst() {
            guard character.isASCII, character.isLetter else { break }
            name.append(character)
        }
        return name.isEmpty ? nil : name
    }

    public static func isKnown(_ name: String) -> Bool {
        SymbolTable.symbols[name] != nil
            || TextOperators.operators[name] != nil
            || UnsupportedCommands.reasons[name] != nil
            || structural.contains(name)
    }

    /// True when the candidate opens with a command someone could reasonably
    /// have meant, whether or not it converts.
    public static func looksIntentional(_ candidate: String) -> Bool {
        guard let name = leadingCommandName(of: candidate) else { return false }
        return isKnown(name)
    }
}
