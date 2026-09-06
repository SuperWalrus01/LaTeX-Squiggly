import InputTracking
import LaTeXUnicode

func runInputTrackingChecks(_ c: Checker) {

    // MARK: Buffer

    var buffer = InputBuffer(capacity: 8)
    buffer.insert("abc")
    c.equal(buffer.text, "abc", "buffer accumulates")
    buffer.deleteBackward()
    c.equal(buffer.text, "ab", "backspace removes one character")
    buffer.insert("cdefghij")
    c.equal(buffer.text, "cdefghij", "buffer is bounded to its capacity")
    c.equal(buffer.text.count, 8, "capacity respected")
    buffer.reset()
    c.equal(buffer.text, "", "reset clears")
    buffer.deleteBackward()
    c.equal(buffer.text, "", "backspace on empty is harmless")

    // MARK: What counts as an attempt

    c.equal(KnownCommands.leadingCommandName(of: "\\int_5^6"), "int", "leading name")
    c.equal(KnownCommands.leadingCommandName(of: "\\alpha"), "alpha", "leading name")
    c.equal(KnownCommands.leadingCommandName(of: "alpha"), nil, "no backslash, no name")
    c.equal(KnownCommands.leadingCommandName(of: "\\"), nil, "lone backslash")
    c.equal(KnownCommands.leadingCommandName(of: "\\{"), nil, "control symbol is not a name")

    c.expect(KnownCommands.looksIntentional("\\alpha"), "\\alpha is a real attempt")
    c.expect(KnownCommands.looksIntentional("\\vec{v}"), "\\vec is recognised even though refused")
    c.expect(KnownCommands.looksIntentional("\\frac{1}{2}"), "structural commands count")
    c.expect(!KnownCommands.looksIntentional("\\Users"), "a Windows path is not an attempt")
    c.expect(!KnownCommands.looksIntentional("\\foo"), "an unknown command is not an attempt")

    // MARK: Trigger outcomes

    func outcome(_ buffer: String, _ terminator: Character = " ") -> TriggerOutcome {
        TriggerDetector.outcome(buffer: buffer, terminator: terminator)
    }

    c.equal(outcome("\\alpha"),
            .replace(Replacement(deleteCount: 6, insert: "α ", notice: nil)),
            "clean conversion carries the terminator back")

    c.equal(outcome("\\int_5^6"),
            .replace(Replacement(deleteCount: 8, insert: "∫₅⁶ ", notice: nil)),
            "scripts convert")

    c.equal(outcome("\\alpha", "\t"),
            .replace(Replacement(deleteCount: 6, insert: "α\t", notice: nil)),
            "tab is a terminator too")

    // Only the trailing command is replaced, not everything typed before it.
    c.equal(outcome("Let \\alpha"),
            .replace(Replacement(deleteCount: 6, insert: "α ", notice: nil)),
            "preceding prose is left alone")

    // A fallback still replaces, but must carry an explanation.
    if case .replace(let r) = outcome("\\frac{1}{2}") {
        c.equal(r.insert, "1/2 ", "fallback text")
        c.equal(r.deleteCount, 11, "fallback delete count")
        c.notNil(r.notice, "a fallback must carry a notice")
    } else {
        c.fail("expected a fallback replacement for \\frac{1}{2}")
    }

    // A recognised command with no honest form: say so, change nothing.
    if case .refuse(let source, let reason) = outcome("\\vec{v}") {
        c.equal(source, "\\vec{v}", "refusal reports what was typed")
        c.expect(reason.lowercased().contains("accent"), "refusal explains: \(reason)")
    } else {
        c.fail("expected a refusal for \\vec{v}")
    }

    if case .refuse = outcome("\\alpha_b") {
        // Opens with a real command, so the missing subscript is worth saying.
    } else {
        c.fail("expected a refusal for \\alpha_b")
    }

    // MARK: Staying quiet

    c.equal(outcome("hello"), .none, "ordinary prose does not fire")
    c.equal(outcome("x^2"), .none, "bare scripts do not fire without a command")
    c.equal(outcome("2^3"), .none, "arithmetic in prose is left alone")
    c.equal(outcome("a_b"), .none, "identifiers are left alone")
    c.equal(outcome("C:\\Users"), .none, "a Windows path is left alone")
    c.equal(outcome("\\foo"), .none, "an unknown command stays silent")
    c.equal(outcome("\\"), .none, "a lone backslash does nothing")
    c.equal(outcome(""), .none, "an empty buffer does nothing")
    c.equal(outcome("\\alpha beta"), .none, "an already-terminated command does not re-fire")

    // Return is not a terminator, so it can never race a message send.
    c.expect(!TriggerDetector.terminators.contains("\n"), "return must not trigger")
    c.expect(TriggerDetector.terminators.contains(" "), "space triggers")
    c.expect(TriggerDetector.terminators.contains("\t"), "tab triggers")

    // MARK: Delete counts are exact

    // The count must match the characters actually typed, or the app eats the
    // user's other text.
    for source in ["\\alpha", "\\int_5^6", "\\sum_{i=1}^{n}", "\\R", "\\leq"] {
        if case .replace(let r) = outcome(source) {
            c.equal(r.deleteCount, source.count, "delete count for \(source)")
        } else {
            c.fail("expected a replacement for \(source)")
        }
    }
}
