/// A named collection of expectations.
public struct CheckGroup {
    public let name: String
    public let run: (Checker) -> Void
}

/// The whole test suite, in one place, runnable from either
/// `latex-squiggly-check` or `swift test`.
public enum CheckSuite {

    public static let groups: [CheckGroup] = [
        CheckGroup(name: "Codepoints", run: runCodepointChecks),
        CheckGroup(name: "Table integrity", run: runTableIntegrityChecks),
        CheckGroup(name: "Tokenizer", run: runTokenizerChecks),
        CheckGroup(name: "Prefix collisions", run: runPrefixCollisionChecks),
        CheckGroup(name: "Scripts", run: runScriptChecks),
        CheckGroup(name: "Fallbacks", run: runFallbackChecks),
        CheckGroup(name: "Conversion", run: runConversionChecks),
        CheckGroup(name: "Input tracking", run: runInputTrackingChecks),
        CheckGroup(name: "Suppression", run: runSuppressionChecks),
    ]

    /// Runs one group and returns its checker.
    public static func run(_ group: CheckGroup) -> Checker {
        let checker = Checker()
        group.run(checker)
        return checker
    }
}
