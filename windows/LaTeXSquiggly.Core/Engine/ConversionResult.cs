namespace LaTeXSquiggly.Core.Engine;

/// <summary>
/// The outcome of converting a LaTeX fragment to inline Unicode.
///
/// The app never produces an image, so some LaTeX has no faithful Unicode form.
/// Every such case is reported explicitly. A half-converted string is never
/// returned: if any part of the input cannot be represented, the whole
/// conversion is Unsupported and the caller must leave the user's text alone.
/// </summary>
public enum ConversionKind
{
    /// <summary>Every token had a faithful form. Safe to substitute silently.</summary>
    Converted,

    /// <summary>
    /// An honest linear approximation. The caller <b>must</b> tell the user that
    /// a fallback happened. Substituting this silently is the failure mode the
    /// app exists to avoid.
    /// </summary>
    Fallback,

    /// <summary>
    /// Nothing sensible exists. The caller <b>must</b> leave the input untouched
    /// and surface the reason.
    /// </summary>
    Unsupported,
}

public sealed class ConversionResult : IEquatable<ConversionResult>
{
    public ConversionKind Kind { get; }

    /// <summary>The replacement text, or null when nothing should be substituted.</summary>
    public string? Text { get; }

    /// <summary>The explanation the user needs, or null when the conversion was clean.</summary>
    public string? Reason { get; }

    private ConversionResult(ConversionKind kind, string? text, string? reason)
    {
        Kind = kind;
        Text = text;
        Reason = reason;
    }

    public static ConversionResult Converted(string text) => new(ConversionKind.Converted, text, null);

    public static ConversionResult Fallback(string text, string reason) =>
        new(ConversionKind.Fallback, text, reason);

    public static ConversionResult Unsupported(string reason) =>
        new(ConversionKind.Unsupported, null, reason);

    /// <summary>True when the caller must show the user an explanation.</summary>
    public bool RequiresUserNotice => Kind != ConversionKind.Converted;

    public bool Equals(ConversionResult? other) =>
        other is not null && Kind == other.Kind && Text == other.Text && Reason == other.Reason;

    public override bool Equals(object? obj) => Equals(obj as ConversionResult);

    public override int GetHashCode() => HashCode.Combine(Kind, Text, Reason);
}
