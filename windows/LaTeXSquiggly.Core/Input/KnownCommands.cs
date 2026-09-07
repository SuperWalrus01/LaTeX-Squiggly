using LaTeXSquiggly.Core.Engine;

namespace LaTeXSquiggly.Core.Input;

/// <summary>
/// Decides whether a candidate is a LaTeX attempt at all.
///
/// This is what keeps the app quiet in normal typing. A Windows path like
/// <c>C:\Users </c> reaches the trigger check with a backslash in it, but Users
/// is not a command anyone defined, so nothing fires and nothing is reported.
/// The user is only ever told about a failure they plausibly meant to cause.
/// </summary>
public static class KnownCommands
{
    /// <summary>Commands the converter handles structurally rather than through a table.</summary>
    internal static readonly HashSet<string> Structural = new()
    {
        "frac", "dfrac", "tfrac", "sqrt", "binom", "dbinom", "tbinom",
        "text", "textrm", "mathrm", "operatorname", "mathbb",
        "left", "right", "begin", "end",
    };

    /// <summary>
    /// The command name at the start of the candidate, which must begin with a
    /// backslash. <c>\int_5^6</c> gives "int".
    /// </summary>
    public static string? LeadingCommandName(string candidate)
    {
        if (candidate.Length == 0 || candidate[0] != '\\') return null;
        var name = new System.Text.StringBuilder();
        foreach (var character in candidate.Skip(1))
        {
            if (character >= 128 || !char.IsLetter(character)) break;
            name.Append(character);
        }
        return name.Length == 0 ? null : name.ToString();
    }

    public static bool IsKnown(string name) =>
        SymbolTable.Symbols.ContainsKey(name)
        || TextOperators.Operators.ContainsKey(name)
        || UnsupportedCommands.Reasons.ContainsKey(name)
        || Structural.Contains(name);

    /// <summary>
    /// True when a <c>\x</c> control symbol is one the converter recognises,
    /// whether it converts or is refused. <c>\{</c> and <c>\%</c> qualify,
    /// <c>\@</c> does not.
    /// </summary>
    internal static bool IsKnownControlSymbol(char character) =>
        UnsupportedCommands.EscapedLiterals.ContainsKey(character)
        || UnsupportedCommands.SymbolReasons.ContainsKey(character);

    /// <summary>
    /// True when the candidate opens with a command someone could reasonably
    /// have meant, whether or not it converts.
    /// </summary>
    public static bool LooksIntentional(string candidate)
    {
        var name = LeadingCommandName(candidate);
        return name is not null && IsKnown(name);
    }

    /// <summary>
    /// True when <i>every</i> command in the candidate is one we know and its
    /// braces balance, not merely the one it opens with.
    ///
    /// Deciding to convert does not need this: a conversion that succeeds has
    /// already proved every part of itself. Deciding to report a <i>failure</i>
    /// does. <c>C:\path\to\file</c> opens with <c>\to</c>, a real command, so the
    /// looser rule would announce "Unknown command \file" at somebody typing a
    /// Windows path, which is exactly the silence this type exists to keep.
    /// </summary>
    public static bool IsWhollyIntentional(string candidate)
    {
        var characters = candidate.ToCharArray();
        var index = 0;
        var depth = 0;
        var sawCommand = false;

        while (index < characters.Length)
        {
            switch (characters[index])
            {
                case '\\':
                    index += 1;
                    // A candidate ending in a bare backslash is still being typed.
                    if (index >= characters.Length) return false;
                    if (characters[index] < 128 && char.IsLetter(characters[index]))
                    {
                        var name = new System.Text.StringBuilder();
                        while (index < characters.Length
                               && characters[index] < 128 && char.IsLetter(characters[index]))
                        {
                            name.Append(characters[index]);
                            index += 1;
                        }
                        if (!IsKnown(name.ToString())) return false;
                    }
                    else
                    {
                        if (!IsKnownControlSymbol(characters[index])) return false;
                        index += 1;
                    }
                    sawCommand = true;
                    break;

                case '{':
                    depth += 1;
                    index += 1;
                    break;

                case '}':
                    depth -= 1;
                    if (depth < 0) return false;
                    index += 1;
                    break;

                default:
                    index += 1;
                    break;
            }
        }
        return sawCommand && depth == 0;
    }
}
