/// The outcome of converting a LaTeX fragment to inline Unicode.
///
/// The app never produces an image, so some LaTeX has no faithful Unicode form.
/// Every such case is reported explicitly. A half-converted string is never
/// returned: if any part of the input cannot be represented, the whole
/// conversion is `.unsupported` and the caller must leave the user's text alone.
public enum ConversionResult: Equatable {

    /// Every token had a faithful Unicode representation. Safe to substitute
    /// silently.
    case converted(String)

    /// An honest linear approximation was produced — for example
    /// `\frac{x+1}{y-2}` as `(x+1)/(y-2)`.
    ///
    /// The caller **must** tell the user that a fallback happened and what it
    /// produced. Substituting this silently is the failure mode the app exists
    /// to avoid.
    case fallback(String, reason: String)

    /// Nothing sensible exists. The caller **must** leave the input untouched
    /// and surface `reason`.
    case unsupported(reason: String)
}

public extension ConversionResult {

    /// The replacement text, or `nil` when nothing should be substituted.
    var text: String? {
        switch self {
        case .converted(let s):    return s
        case .fallback(let s, _):  return s
        case .unsupported:         return nil
        }
    }

    /// The explanation the user needs to see, or `nil` when the conversion was
    /// clean.
    var reason: String? {
        switch self {
        case .converted:              return nil
        case .fallback(_, let r):     return r
        case .unsupported(let r):     return r
        }
    }

    /// True when the caller must show the user an explanation before or
    /// alongside the substitution.
    var requiresUserNotice: Bool {
        if case .converted = self { return false }
        return true
    }
}
