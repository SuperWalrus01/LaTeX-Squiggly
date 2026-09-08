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

    func outcome(_ buffer: String, _ terminator: Character = " ",
                 options: ConversionOptions = .default) -> TriggerOutcome {
        TriggerDetector.outcome(buffer: buffer, terminator: terminator, options: options)
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
    if case .replace(let r) = outcome("\\frac{a}{b}") {
        c.equal(r.insert, "a\u{2215}b ", "fallback text")
        c.equal(r.deleteCount, 11, "fallback delete count")
        c.notNil(r.notice, "a fallback must carry a notice")
    } else {
        c.fail("expected a fallback replacement for \\frac{a}{b}")
    }

    // An exact fraction needs no notice at all.
    if case .replace(let r) = outcome("\\frac{1}{2}") {
        c.equal(r.insert, "\u{00BD} ", "exact fraction")
        c.isNil(r.notice, "an exact fraction carries no notice")
    } else {
        c.fail("expected a replacement for \\frac{1}{2}")
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


    // MARK: $...$ maths delimiters

    // The whole point: bare scripts become reachable without making every
    // caret in prose dangerous.
    c.equal(outcome("$x^2$"),
            .replace(Replacement(deleteCount: 5, insert: "x\u{00B2} ", notice: nil)),
            "$x^2$ converts, delimiters included in the delete count")
    c.equal(outcome("$a_1$"),
            .replace(Replacement(deleteCount: 5, insert: "a\u{2081} ", notice: nil)),
            "subscripts too")
    c.equal(outcome("$\\alpha$"),
            .replace(Replacement(deleteCount: 8, insert: "\u{03B1} ", notice: nil)),
            "commands work inside delimiters")

    // Whitespace inside is fine; a whole expression is the point.
    c.equal(outcome("$\\alpha + x^2$"),
            .replace(Replacement(deleteCount: 14, insert: "\u{03B1} + x\u{00B2} ", notice: nil)),
            "multi-token expressions convert in one go")

    // Only the delimited span is touched, not the prose before it.
    if case .replace(let r) = outcome("let me write $x^2$") {
        c.equal(r.deleteCount, 5, "preceding prose survives")
        c.equal(r.insert, "x\u{00B2} ", "preceding prose survives")
    } else {
        c.fail("expected a replacement after prose")
    }

    // Currency must never convert. This is why a span has to contain a
    // backslash, caret or underscore to count as maths.
    c.equal(outcome("$5$"), TriggerOutcome.none, "$5$ is money, not maths")
    c.equal(outcome("I have $5$"), TriggerOutcome.none, "money in a sentence")
    c.equal(outcome("$100$"), TriggerOutcome.none, "larger amounts too")
    c.equal(outcome("it cost $5 and $10"), TriggerOutcome.none, "two amounts, no closing span")
    c.equal(outcome("$x$"), TriggerOutcome.none, "nothing to convert, so nothing fires")

    // Malformed spans stay quiet.
    c.equal(outcome("$x^2"), TriggerOutcome.none, "unclosed span does not fire")
    c.equal(outcome("$$"), TriggerOutcome.none, "empty span does not fire")
    c.equal(outcome("$" + String(repeating: "x^2", count: 30) + "$"), TriggerOutcome.none,
            "an over-long span is refused rather than swallowing the line")

    // A delimited span states intent, so failures are always reported —
    // unlike the backslash path, which stays silent on unknown commands.
    if case .refuse = outcome("$x^q$") {
        // No superscript q exists.
    } else {
        c.fail("expected a refusal for $x^q$")
    }
    if case .replace(let r) = outcome("$\\frac{a}{b}$") {
        c.notNil(r.notice, "a fallback inside delimiters still explains itself")
        c.equal(r.insert, "a\u{2215}b ", "fallback text")
    } else {
        c.fail("expected a fallback for $\\frac{a}{b}$")
    }

    // The backslash path still works unchanged.
    c.equal(outcome("\\alpha"),
            .replace(Replacement(deleteCount: 6, insert: "\u{03B1} ", notice: nil)),
            "backslash commands are unaffected")

    // MARK: Commands inside commands
    //
    // Every trigger check above is a single-command fragment, which is exactly
    // why reading the candidate from the last backslash survived: it is only
    // wrong once a command has another one inside it. `\\frac{\\alpha}{2}` read
    // that way is `\\alpha}{2}`, and the user was told their correct LaTeX had
    // a stray brace.

    if case .replace(let r) = outcome("\\frac{\\alpha}{2}") {
        c.equal(r.deleteCount, 16, "a nested command is replaced whole")
        c.equal(r.insert, "\u{03B1}\u{2215}2 ", "nested fraction text")
        c.notNil(r.notice, "the linear fraction still explains itself")
    } else {
        c.fail("expected a replacement for \\frac{\\alpha}{2}")
    }

    if case .replace(let r) = outcome("\\sqrt{\\alpha}") {
        c.equal(r.deleteCount, 13, "\\sqrt takes its nested argument with it")
    } else {
        c.fail("expected a replacement for \\sqrt{\\alpha}")
    }

    // Two commands in a row are one fragment, not just the last one. Replacing
    // only `\\beta` left `\\alphaβ`, which is the half-converted text the
    // engine's all-or-nothing rule exists to prevent.
    c.equal(outcome("\\alpha\\beta"),
            .replace(Replacement(deleteCount: 11, insert: "\u{03B1}\u{03B2} ", notice: nil)),
            "adjacent commands convert together")

    c.equal(outcome("\\left(\\alpha\\right)"),
            .replace(Replacement(deleteCount: 19, insert: "(\u{03B1}) ", notice: nil)),
            "delimiters and their contents convert together")

    // Prose in front is still untouched, and the count still starts at the
    // backslash rather than at the beginning of the line.
    if case .replace(let r) = outcome("we know \\frac{\\alpha}{2}") {
        c.equal(r.deleteCount, 16, "preceding prose survives a nested command")
    } else {
        c.fail("expected a replacement after prose")
    }

    // A failure inside a nested command must say what is actually wrong.
    if case .refuse(_, let reason) = outcome("\\frac{\\alpha_b}{2}") {
        c.expect(reason.lowercased().contains("subscript"),
                 "a nested failure names the real cause: \(reason)")
    } else {
        c.fail("expected a refusal for \\frac{\\alpha_b}{2}")
    }

    // Earliest start that converts wins, but a start that cannot convert must
    // not block a later one that can.
    if case .replace(let r) = outcome("\\foo\\alpha") {
        c.equal(r.deleteCount, 6, "an unknown leading command does not swallow a real one")
    } else {
        c.fail("expected a replacement for \\foo\\alpha")
    }

    // The silence that pays for all of this. `\\to` is a real command, so a rule
    // that only checked the first one would announce "Unknown command \\file"
    // at somebody typing a Windows path.
    c.equal(outcome("C:\\path\\to\\file"), .none, "a Windows path is still left alone")
    c.equal(outcome("C:\\Users\\me"), .none, "and so is a shorter one")

    c.expect(KnownCommands.isWhollyIntentional("\\frac{\\alpha}{2}"),
             "every command known and braces balanced")
    c.expect(KnownCommands.isWhollyIntentional("\\vec{v}"), "a refused command is still known")
    c.expect(!KnownCommands.isWhollyIntentional("\\to\\file"), "one unknown command is enough")
    c.expect(!KnownCommands.isWhollyIntentional("\\alpha}{2}"), "unbalanced braces are not intentional")
    c.expect(!KnownCommands.isWhollyIntentional("{a}"), "no command at all")
    c.expect(!KnownCommands.isWhollyIntentional("\\alpha\\"), "a trailing backslash is still being typed")

    // MARK: Delete counts are exact

    // The count must match the characters actually typed, or the app eats the
    // user's other text.
    for source in ["\\alpha", "\\int_5^6", "\\sum_{i=1}^{n}", "\\R", "\\leq",
                   "\\frac{\\alpha}{2}", "\\alpha\\beta", "\\left(\\alpha\\right)"] {
        if case .replace(let r) = outcome(source) {
            c.equal(r.deleteCount, source.count, "delete count for \(source)")
        } else {
            c.fail("expected a replacement for \(source)")
        }
    }

    // MARK: Keeping a script Unicode cannot make

    let keep = ConversionOptions(keepUnrenderableScripts: true)

    // Unicode has no raised infinity, so by default this whole expression is a
    // refusal, and the earliest candidate that does convert is the
    // `\infty{a_i}` tail of it. The user is left with the tail replaced inside
    // source that was not: this is the case the option below exists for.
    c.equal(outcome("\\Sigma_{i=1}^\\infty{a_i}"),
            .replace(Replacement(deleteCount: 11, insert: "∞aᵢ ", notice: nil)),
            "by default only the tail that converts is replaced")

    // With the option on the earliest candidate converts, so it wins outright
    // and the tail is never reached.
    if case .replace(let r) = outcome("\\Sigma_{i=1}^\\infty{a_i}", options: keep) {
        c.equal(r.deleteCount, 24, "the whole expression is replaced, not its tail")
        c.equal(r.insert, "Σᵢ₌₁^∞aᵢ ", "every part with a Unicode form gets one")
        c.notNil(r.notice, "a kept script has to be explained")
    } else {
        c.fail("a kept script should still replace")
    }

    // The $...$ path takes the same option, and keeps the spaces inside it.
    if case .replace(let r) = outcome("$\\Sigma_{i=1}^\\infty a_i$", options: keep) {
        c.equal(r.deleteCount, 25, "both delimiters are deleted too")
        c.equal(r.insert, "Σᵢ₌₁^∞ aᵢ ", "a delimited span converts whole")
    } else {
        c.fail("a kept script should replace inside $...$ as well")
    }

    // Off, both paths behave exactly as they did.
    c.equal(outcome("$\\int_0^\\infty$"),
            .refuse(source: "$\\int_0^\\infty$",
                    reason: "There is no Unicode superscript for “∞”."),
            "the default is still a refusal, with its reason")
}
