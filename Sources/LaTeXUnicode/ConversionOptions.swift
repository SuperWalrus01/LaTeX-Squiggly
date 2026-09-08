/// The conversion choices that are the user's to make rather than the engine's.
///
/// Everything else about the engine is fixed: the same fragment produces the
/// same characters on any machine, which is what lets the Windows port be
/// checked against a corpus generated from this one. An option here has to earn
/// its place by being a genuine matter of taste, not a matter of correctness.
///
/// Defaulted throughout, so every existing call site keeps the behaviour it had
/// and the conformance corpus keeps describing the same engine.
public struct ConversionOptions: Equatable, Sendable {

    /// Whether a superscript or subscript with no Unicode form is written back
    /// in the notation it was typed in, instead of failing the whole fragment.
    ///
    /// Unicode has no raised infinity, so `\Sigma_{i=1}^\infty{a_i}` cannot be
    /// converted faithfully. Off, that is `.unsupported` and the caller leaves
    /// the user's text exactly as typed. On, it is a `.fallback` reading
    /// `Σᵢ₌₁^∞aᵢ`: the parts with a form get one, and the part without keeps
    /// its caret.
    ///
    /// Off by default, because it puts converted characters and raw LaTeX on
    /// the same line. Text left alone is always honest about what happened;
    /// mixed text is only sometimes what was wanted.
    public var keepUnrenderableScripts: Bool

    /// What the engine does when nobody has said otherwise.
    public static let `default` = ConversionOptions()

    public init(keepUnrenderableScripts: Bool = false) {
        self.keepUnrenderableScripts = keepUnrenderableScripts
    }
}
