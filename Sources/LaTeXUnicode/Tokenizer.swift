/// A lexical unit of a LaTeX fragment.
public indirect enum Token: Equatable {
    /// `\alpha` → `.command("alpha")`. The backslash is not part of the name.
    case command(String)
    /// A backslash followed by a single non-letter, e.g. `\{` or `\,`.
    case controlSymbol(Character)
    /// Any other character, including the whitespace that terminated a command.
    case character(Character)
    /// A `{ ... }` group.
    case group([Token])
    /// `^`
    case sup
    /// `_`
    case sub
}

public enum TokenizerError: Error, Equatable {
    case unbalancedBrace
    case unexpectedClosingBrace
    case danglingBackslash

    public var reason: String {
        switch self {
        case .unbalancedBrace:
            return "Unbalanced braces — a `{` was never closed."
        case .unexpectedClosingBrace:
            return "Unbalanced braces — a `}` has no matching `{`."
        case .danglingBackslash:
            return "The input ends with a lone backslash."
        }
    }
}

public enum Tokenizer {

    /// Splits a LaTeX fragment into tokens.
    ///
    /// **Longest match.** A command name is a backslash followed by the longest
    /// possible run of ASCII letters. This is what resolves the prefix family
    /// `\in` / `\inf` / `\infty` / `\int`: scanning is greedy, so `\int` can
    /// never be read as `\in` followed by a literal `t`.
    ///
    /// **Terminators are preserved.** A command name ends at the first
    /// non-letter. That character is *not* consumed — it is emitted as an
    /// ordinary token, so `\alpha ` converts to `α ` with the space intact.
    /// This deliberately diverges from TeX, which swallows the space after a
    /// control word. In running prose, eating the space is the wrong default:
    /// `\alpha + \beta ` should read `α + β`, not `α+ β`.
    public static func tokenize(_ input: String) throws -> [Token] {
        let chars = Array(input)
        var i = 0
        let tokens = try scan(chars, &i, depth: 0)
        // A `}` at depth 0 stops the scan; anything left over is unmatched.
        guard i == chars.count else { throw TokenizerError.unexpectedClosingBrace }
        return tokens
    }

    private static func scan(_ c: [Character], _ i: inout Int, depth: Int) throws -> [Token] {
        var out: [Token] = []
        while i < c.count {
            switch c[i] {
            case "\\":
                i += 1
                guard i < c.count else { throw TokenizerError.danglingBackslash }
                if isCommandLetter(c[i]) {
                    var name = ""
                    while i < c.count, isCommandLetter(c[i]) {
                        name.append(c[i])
                        i += 1
                    }
                    out.append(.command(name))
                } else {
                    out.append(.controlSymbol(c[i]))
                    i += 1
                }

            case "{":
                i += 1
                let inner = try scan(c, &i, depth: depth + 1)
                guard i < c.count, c[i] == "}" else { throw TokenizerError.unbalancedBrace }
                i += 1
                out.append(.group(inner))

            case "}":
                // Let the caller consume it; at depth 0 tokenize() rejects it.
                return out

            case "^":
                out.append(.sup)
                i += 1

            case "_":
                out.append(.sub)
                i += 1

            default:
                out.append(.character(c[i]))
                i += 1
            }
        }
        if depth > 0 { throw TokenizerError.unbalancedBrace }
        return out
    }

    private static func isCommandLetter(_ ch: Character) -> Bool {
        ch.isASCII && ch.isLetter
    }
}
