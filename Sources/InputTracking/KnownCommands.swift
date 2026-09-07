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

    /// True when a backslash followed by a single non-letter is one the
    /// converter recognises. `\\{` and `\\%` qualify, `\\@` does not.
    static func isKnownControlSymbol(_ character: Character) -> Bool {
        UnsupportedCommands.escapedLiterals[character] != nil
            || UnsupportedCommands.symbolReasons[character] != nil
    }

    /// True when the candidate opens with a command someone could reasonably
    /// have meant, whether or not it converts.
    public static func looksIntentional(_ candidate: String) -> Bool {
        guard let name = leadingCommandName(of: candidate) else { return false }
        return isKnown(name)
    }

    /// True when *every* command in the candidate is one we know and its braces
    /// balance, not merely the one it opens with.
    ///
    /// Deciding to convert does not need this: a conversion that succeeds has
    /// already proved every part of itself. Deciding to report a *failure*
    /// does. `C:\\path\\to\\file` opens with `\\to`, a real command, so the looser
    /// rule would announce "Unknown command \\file" at somebody typing a
    /// Windows path, which is exactly the silence this type exists to keep.
    public static func isWhollyIntentional(_ candidate: String) -> Bool {
        let characters = Array(candidate)
        var index = 0
        var depth = 0
        var sawCommand = false

        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 1
                // A candidate ending in a bare backslash is still being typed.
                guard index < characters.count else { return false }
                if characters[index].isASCII, characters[index].isLetter {
                    var name = ""
                    while index < characters.count,
                          characters[index].isASCII, characters[index].isLetter {
                        name.append(characters[index])
                        index += 1
                    }
                    guard isKnown(name) else { return false }
                } else {
                    guard isKnownControlSymbol(characters[index]) else { return false }
                    index += 1
                }
                sawCommand = true

            case "{":
                depth += 1
                index += 1

            case "}":
                depth -= 1
                guard depth >= 0 else { return false }
                index += 1

            default:
                index += 1
            }
        }
        return sawCommand && depth == 0
    }
}
