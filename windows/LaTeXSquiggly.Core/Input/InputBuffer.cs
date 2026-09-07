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

    public void Insert(string text)
    {
        _text += text;
        var overflow = Text_.CharacterCount(_text) - Capacity;
        if (overflow > 0)
        {
            _text = Trimmed(_text, overflow);
        }
    }

    public void DeleteBackward()
    {
        if (_text.Length == 0) return;
        var characters = Core.Text.Characters(_text).ToList();
        characters.RemoveAt(characters.Count - 1);
        _text = string.Concat(characters);
    }

    /// <summary>
    /// Called whenever we can no longer trust that the buffer reflects what is
    /// in front of the cursor: a click, an arrow key, an app switch, Return.
    /// </summary>
    public void Reset() => _text = "";

    private static string Trimmed(string text, int dropped) =>
        string.Concat(Core.Text.Characters(text).Skip(dropped));
}

internal static class Text_
{
    public static int CharacterCount(string text) => Core.Text.CharacterCount(text);
}
