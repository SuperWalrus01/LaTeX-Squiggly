namespace LaTeXSquiggly.Core.Input;

/// <summary>
/// A short rolling record of what the user has just typed.
///
/// In memory only, bounded, and cleared aggressively. Nothing here is ever
/// written to disk or sent anywhere.
/// </summary>
public sealed class InputBuffer
{
    /// <summary>
    /// Long enough for any realistic command plus scripts, short enough that
    /// the buffer never accumulates a sentence.
    /// </summary>
    public const int DefaultCapacity = 64;

    private string _text = "";
    public int Capacity { get; }

    public InputBuffer(int capacity = DefaultCapacity) => Capacity = capacity;

    public string Text => _text;

    public bool IsEmpty => _text.Length == 0;

    /// <summary>
    /// True when the buffer holds something a terminator could act on: a
    /// backslash, or a dollar.
    ///
    /// The trigger rules only ever fire on a candidate starting with a backslash
    /// or on a <c>$...$</c> span, so a buffer with neither cannot produce a
    /// replacement no matter what is typed next. That makes this the exact
    /// answer to "does it matter right now whether this buffer is stale", which
    /// is what the Windows app uses to decide whether watching the mouse is
    /// worth anything: see InputThread.
    /// </summary>
    public bool CanTrigger { get; private set; }

    public void Insert(string text)
    {
        _text += text;
        // The buffer is at most 64 characters and almost always plain ASCII, so
        // the length is the character count and no overflow is possible until
        // the string itself is over capacity. Checking that first keeps the
        // grapheme walk off the path every keystroke takes.
        if (_text.Length <= Capacity)
        {
            Recompute();
            return;
        }

        var overflow = Text_.CharacterCount(_text) - Capacity;
        if (overflow > 0)
        {
            _text = Trimmed(_text, overflow);
        }
        Recompute();
    }

    public void DeleteBackward()
    {
        if (_text.Length == 0) return;

        // An ASCII buffer has one character per code unit, which is the case
        // for LaTeX source and for ordinary typing in it. Anything else is
        // walked properly, because a grapheme cluster removed by halves would
        // put the wrong number in the one place the number must be right: how
        // many backspaces get typed.
        if (IsAscii(_text))
        {
            _text = _text[..^1];
            Recompute();
            return;
        }

        var characters = Core.Text.Characters(_text).ToList();
        characters.RemoveAt(characters.Count - 1);
        _text = string.Concat(characters);
        Recompute();
    }

    /// <summary>
    /// A scan of at most 64 characters after each change, rather than a flag
    /// kept in step by hand. Trimming for overflow can drop the only backslash
    /// in the buffer, so an incrementally maintained flag would have to be
    /// undone in a place that is easy to forget.
    /// </summary>
    private void Recompute()
    {
        foreach (var character in _text)
        {
            if (character is '\\' or '$') { CanTrigger = true; return; }
        }
        CanTrigger = false;
    }

    private static bool IsAscii(string text)
    {
        foreach (var character in text)
        {
            if (character > 0x7F) return false;
        }
        return true;
    }

    /// <summary>
    /// Called whenever we can no longer trust that the buffer reflects what is
    /// in front of the cursor: a click, an arrow key, an app switch, Return.
    /// </summary>
    public void Reset()
    {
        _text = "";
        CanTrigger = false;
    }

    private static string Trimmed(string text, int dropped) =>
        string.Concat(Core.Text.Characters(text).Skip(dropped));
}

internal static class Text_
{
    public static int CharacterCount(string text) => Core.Text.CharacterCount(text);
}
