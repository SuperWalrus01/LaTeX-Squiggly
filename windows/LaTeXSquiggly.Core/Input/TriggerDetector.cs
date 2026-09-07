using LaTeXSquiggly.Core.Engine;

namespace LaTeXSquiggly.Core.Input;

public enum TriggerKind
{
    /// <summary>Nothing was pending. Let the keystroke through untouched.</summary>
    None,

    /// <summary>Replace typed source with Unicode.</summary>
    Replace,

    /// <summary>
    /// A real LaTeX attempt with no honest Unicode form. Leave the text alone
    /// and tell the user why.
    /// </summary>
    Refuse,
}

public sealed record Replacement(int DeleteCount, string Insert, string? Notice);

public sealed record TriggerOutcome(TriggerKind Kind, Replacement? Replacement, string? Source, string? Reason)
{
    public static readonly TriggerOutcome None = new(TriggerKind.None, null, null, null);

    public static TriggerOutcome Replace(Replacement replacement) =>
        new(TriggerKind.Replace, replacement, null, null);

    public static TriggerOutcome Refuse(string source, string reason) =>
        new(TriggerKind.Refuse, null, source, reason);
}

public static class TriggerDetector
{
    /// <summary>
    /// Keystrokes that complete a command.
    ///
    /// Space and tab only. Return is deliberately excluded: in a chat app it
    /// sends the message, and racing a replacement against a send is a good way
    /// to post half a symbol.
    /// </summary>
    public static readonly IReadOnlySet<char> Terminators = new HashSet<char> { ' ', '\t' };

    /// <summary>
    /// Longest <c>$...$</c> span we will consider, so a stray dollar earlier in
    /// the sentence cannot swallow half a line.
    /// </summary>
    internal const int MaximumDelimitedLength = 48;

    /// <summary>
    /// Characters that make a <c>$...$</c> span worth converting. Without this,
    /// "I have $5$ left" would rewrite itself.
    /// </summary>
    private static readonly IReadOnlySet<char> MathematicalSignals =
        new HashSet<char> { '\\', '^', '_' };

    /// <summary>
    /// Handles LaTeX's own inline maths delimiters, which is how bare scripts
    /// become reachable. <c>x^2</c> on its own must never fire, because 2^3 in a
    /// sentence and a_b in an identifier would rewrite themselves, but
    /// <c>$x^2$</c> is something nobody types by accident.
    ///
    /// Unlike the backslash path, a failure here is always reported: wrapping
    /// something in <c>$...$</c> is a clear statement of intent.
    /// </summary>
    /// <returns>Null when this is not a delimited span, so the caller can fall
    /// through to the backslash rule.</returns>
    private static TriggerOutcome? MathDelimited(string buffer, char terminator)
    {
        if (buffer.Length == 0 || buffer[^1] != '$') return null;
        var beforeClosing = buffer[..^1];
        var opening = beforeClosing.LastIndexOf('$');
        if (opening < 0) return null;

        var content = beforeClosing[(opening + 1)..];
        if (content.Length == 0
            || Core.Text.CharacterCount(content) > MaximumDelimitedLength
            || !content.Any(MathematicalSignals.Contains))
        {
            return null;
        }

        // Both delimiters are typed source and have to be deleted too.
        var deleteCount = Core.Text.CharacterCount(content) + 2;

        var result = Converter.Convert(content);
        return result.Kind switch
        {
            ConversionKind.Converted =>
                TriggerOutcome.Replace(new Replacement(deleteCount, result.Text + terminator, null)),
            ConversionKind.Fallback =>
                TriggerOutcome.Replace(new Replacement(deleteCount, result.Text + terminator, result.Reason)),
            _ => TriggerOutcome.Refuse("$" + content + "$", result.Reason!),
        };
    }

    /// <summary>
    /// Every point at which a candidate could begin, earliest first.
    ///
    /// Whitespace ends a command, so only the run of typing since the last space
    /// can still be pending; within that run, every backslash is a possible
    /// start.
    ///
    /// Earliest first is the whole fix for nested commands. Read from its
    /// <i>last</i> backslash, <c>\frac{\alpha}{2}</c> is <c>\alpha}{2}</c>, which
    /// really is unbalanced, so the app told the user their correct LaTeX had a
    /// stray brace. Read from its first, it is the fragment they actually typed.
    /// </summary>
    private static List<string> CandidateStarts(string buffer)
    {
        var runStart = 0;
        for (var i = buffer.Length - 1; i >= 0; i--)
        {
            if (char.IsWhiteSpace(buffer[i])) { runStart = i + 1; break; }
        }
        var starts = new List<string>();
        for (var i = runStart; i < buffer.Length; i++)
        {
            if (buffer[i] == '\\') starts.Add(buffer[i..]);
        }
        return starts;
    }

    /// <summary>
    /// Decides what to do given the buffer and the terminator just typed.
    ///
    /// The terminator is assumed to have been suppressed by the caller, so
    /// DeleteCount covers only the command source and Insert carries the
    /// terminator back.
    ///
    /// Two things can fire. A <c>$...$</c> span converts whatever is between the
    /// delimiters. Otherwise the candidate must start with a backslash, and the
    /// earliest start that converts wins, so a command and its arguments are
    /// replaced together instead of the innermost one being picked out of the
    /// middle of them.
    /// </summary>
    public static TriggerOutcome Outcome(string buffer, char terminator)
    {
        // Explicit maths first: $x^2$ is unambiguous where bare x^2 is not.
        var delimited = MathDelimited(buffer, terminator);
        if (delimited is not null) return delimited;

        // Held rather than returned, so a start that cannot convert does not
        // stop a later one that can. \foo\alpha still converts its alpha.
        TriggerOutcome? refusal = null;

        foreach (var candidate in CandidateStarts(buffer))
        {
            // A lone backslash is not a pending command.
            if (Core.Text.CharacterCount(candidate) <= 1) continue;
            if (!KnownCommands.LooksIntentional(candidate)) continue;

            var result = Converter.Convert(candidate);
            var deleteCount = Core.Text.CharacterCount(candidate);
            switch (result.Kind)
            {
                case ConversionKind.Converted:
                    return TriggerOutcome.Replace(
                        new Replacement(deleteCount, result.Text + terminator, null));

                case ConversionKind.Fallback:
                    return TriggerOutcome.Replace(
                        new Replacement(deleteCount, result.Text + terminator, result.Reason));

                default:
                    // Say why only when the whole candidate is LaTeX the user
                    // plainly meant. A half-recognised run, \to\file inside a
                    // Windows path, stays as quiet as it was before.
                    if (refusal is null && KnownCommands.IsWhollyIntentional(candidate))
                    {
                        refusal = TriggerOutcome.Refuse(candidate, result.Reason!);
                    }
                    break;
            }
        }
        return refusal ?? TriggerOutcome.None;
    }
}
