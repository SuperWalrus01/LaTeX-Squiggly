using System.Globalization;

namespace LaTeXSquiggly.Core;

/// <summary>
/// Counting characters the way Swift does.
///
/// Swift's <c>Character</c> is a grapheme cluster; C#'s <c>char</c> is a UTF-16
/// code unit. For LaTeX source the two agree, because it is ASCII, but not for
/// what the engine produces: the double-struck alphabet lives outside the basic
/// plane, so <c>\mathbb{X}</c> is one Swift Character and two C# chars. That
/// difference decides whether a fraction gets parentheses and how a refusal
/// names the character it could not convert, so it has to be got right rather
/// than assumed away.
///
/// It also decides how many backspaces get typed, which is the one number in
/// this program that must never be wrong.
/// </summary>
public static class Text
{
    /// <summary>The number of user-perceived characters, as Swift counts them.</summary>
    public static int CharacterCount(string text)
    {
        if (IsAscii(text)) return text.Length;
        var count = 0;
        var enumerator = StringInfo.GetTextElementEnumerator(text);
        while (enumerator.MoveNext()) count += 1;
        return count;
    }

    /// <summary>The user-perceived characters, in order.</summary>
    public static IEnumerable<string> Characters(string text)
    {
        var enumerator = StringInfo.GetTextElementEnumerator(text);
        while (enumerator.MoveNext())
        {
            yield return (string)enumerator.Current;
        }
    }

    private static bool IsAscii(string text)
    {
        foreach (var ch in text)
        {
            if (ch > 0x7F) return false;
        }
        return true;
    }
}
