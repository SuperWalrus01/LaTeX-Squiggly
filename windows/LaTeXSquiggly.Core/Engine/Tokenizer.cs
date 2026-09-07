namespace LaTeXSquiggly.Core.Engine;

/// <summary>A lexical unit of a LaTeX fragment.</summary>
public abstract record Token
{
    /// <summary><c>\alpha</c> becomes Command("alpha"). The backslash is not part of the name.</summary>
    public sealed record Command(string Name) : Token;

    /// <summary>A backslash followed by a single non-letter, such as <c>\{</c> or <c>\,</c>.</summary>
    public sealed record ControlSymbol(char Symbol) : Token;

    /// <summary>Any other character, including whitespace that terminated a command.</summary>
    public sealed record Character(char Value) : Token;

    /// <summary>A <c>{ ... }</c> group.</summary>
    public sealed record Group(IReadOnlyList<Token> Inner) : Token;

    public sealed record Sup : Token;

    public sealed record Sub : Token;
}

public enum TokenizerErrorKind { UnbalancedBrace, UnexpectedClosingBrace, DanglingBackslash }

public sealed class TokenizerException : Exception
{
    public TokenizerErrorKind Kind { get; }

    public TokenizerException(TokenizerErrorKind kind) : base(ReasonFor(kind)) => Kind = kind;

    private static string ReasonFor(TokenizerErrorKind kind) => kind switch
    {
        TokenizerErrorKind.UnbalancedBrace =>
            "Unbalanced braces — a `{` was never closed.",
        TokenizerErrorKind.UnexpectedClosingBrace =>
            "Unbalanced braces — a `}` has no matching `{`.",
        _ => "The input ends with a lone backslash.",
    };
}

public static class Tokenizer
{
    /// <summary>
    /// Splits a LaTeX fragment into tokens.
    ///
    /// <b>Longest match.</b> A command name is a backslash followed by the
    /// longest possible run of ASCII letters. This is what resolves the prefix
    /// family <c>\in</c> / <c>\inf</c> / <c>\infty</c> / <c>\int</c>: scanning is
    /// greedy, so <c>\int</c> can never be read as <c>\in</c> then a literal t.
    ///
    /// <b>Terminators are preserved.</b> A command name ends at the first
    /// non-letter, and that character is emitted as an ordinary token rather
    /// than consumed, so <c>\alpha </c> converts to "a " with the space intact.
    /// This diverges from TeX, which swallows the space after a control word;
    /// in running prose, eating the space is the wrong default.
    /// </summary>
    public static IReadOnlyList<Token> Tokenize(string input)
    {
        var characters = input.ToCharArray();
        var index = 0;
        var tokens = Scan(characters, ref index, depth: 0);
        // A `}` at depth 0 stops the scan; anything left over is unmatched.
        if (index != characters.Length)
        {
            throw new TokenizerException(TokenizerErrorKind.UnexpectedClosingBrace);
        }
        return tokens;
    }

    private static List<Token> Scan(char[] c, ref int i, int depth)
    {
        var output = new List<Token>();
        while (i < c.Length)
        {
            switch (c[i])
            {
                case '\\':
                    i += 1;
                    if (i >= c.Length)
                    {
                        throw new TokenizerException(TokenizerErrorKind.DanglingBackslash);
                    }
                    if (IsCommandLetter(c[i]))
                    {
                        var name = new System.Text.StringBuilder();
                        while (i < c.Length && IsCommandLetter(c[i]))
                        {
                            name.Append(c[i]);
                            i += 1;
                        }
                        output.Add(new Token.Command(name.ToString()));
                    }
                    else
                    {
                        output.Add(new Token.ControlSymbol(c[i]));
                        i += 1;
                    }
                    break;

                case '{':
                {
                    i += 1;
                    var inner = Scan(c, ref i, depth + 1);
                    if (i >= c.Length || c[i] != '}')
                    {
                        throw new TokenizerException(TokenizerErrorKind.UnbalancedBrace);
                    }
                    i += 1;
                    output.Add(new Token.Group(inner));
                    break;
                }

                case '}':
                    // Let the caller consume it; at depth 0 Tokenize rejects it.
                    return output;

                case '^':
                    output.Add(new Token.Sup());
                    i += 1;
                    break;

                case '_':
                    output.Add(new Token.Sub());
                    i += 1;
                    break;

                default:
                    output.Add(new Token.Character(c[i]));
                    i += 1;
                    break;
            }
        }
        if (depth > 0)
        {
            throw new TokenizerException(TokenizerErrorKind.UnbalancedBrace);
        }
        return output;
    }

    private static bool IsCommandLetter(char ch) => ch < 128 && char.IsLetter(ch);
}
