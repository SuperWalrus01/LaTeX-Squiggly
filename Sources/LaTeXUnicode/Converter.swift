/// Converts a LaTeX fragment to inline Unicode.
///
/// Accepts a whole fragment, not just a single command: literal text passes
/// through untouched, so `convert("x^2 + \\alpha")` yields `x² + α`.
///
/// The result is all-or-nothing. If any part of the input has no faithful
/// Unicode form, the whole call returns `.unsupported` — a half-converted
/// string is never produced.
public func convert(_ latex: String) -> ConversionResult {
    guard !latex.isEmpty else {
        return .unsupported(reason: "There is nothing to convert.")
    }
    do {
        let rendered = try Renderer.render(try Tokenizer.tokenize(latex))
        guard !rendered.fallbacks.isEmpty else {
            return .converted(rendered.text)
        }
        return .fallback(rendered.text, reason: deduplicated(rendered.fallbacks).joined(separator: " "))
    } catch let error as UnsupportedInput {
        return .unsupported(reason: error.reason)
    } catch let error as TokenizerError {
        return .unsupported(reason: error.reason)
    } catch {
        return .unsupported(reason: "The input could not be parsed.")
    }
}

// MARK: - Internals

private struct Rendered {
    var text = ""
    var fallbacks: [String] = []

    mutating func append(_ other: Rendered) {
        text += other.text
        fallbacks += other.fallbacks
    }
}

private struct UnsupportedInput: Error {
    let reason: String
}

private enum ScriptKind {
    case sup, sub

    var name: String { self == .sup ? "superscript" : "subscript" }
    var marker: Character { self == .sup ? "^" : "_" }
    var table: [Character: Character] {
        self == .sup ? ScriptTables.superscripts : ScriptTables.subscripts
    }
}

private struct Renderer {
    let tokens: [Token]
    var index = 0
    var out = Rendered()

    static func render(_ tokens: [Token]) throws -> Rendered {
        var renderer = Renderer(tokens: tokens)
        try renderer.run()
        return renderer.out
    }

    private mutating func run() throws {
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            switch token {
            case .character(let c):     out.text.append(c)
            case .group(let inner):     out.append(try Renderer.render(inner))
            case .sup:                  try applyScript(.sup)
            case .sub:                  try applyScript(.sub)
            case .controlSymbol(let c): try emit(controlSymbol: c)
            case .command(let name):    try emit(command: name)
            }
        }
    }

    /// The next argument: a braced group's contents, or a single token.
    /// `\frac12` and `\frac{1}{2}` therefore behave the same, as in LaTeX.
    ///
    /// Whitespace before an argument is skipped, so `\mathbb R` and `\frac 1 2`
    /// work. This does not contradict the tokenizer's rule that a command's
    /// terminator is preserved: that rule is about symbol commands, which take
    /// no argument and so never reach this method.
    private mutating func nextUnit() -> [Token]? {
        while index < tokens.count,
              case .character(let c) = tokens[index], c.isWhitespace {
            index += 1
        }
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        index += 1
        if case .group(let inner) = token { return inner }
        return [token]
    }

    // MARK: Scripts

    private mutating func applyScript(_ kind: ScriptKind) throws {
        guard let unit = nextUnit() else {
            throw UnsupportedInput(reason: "`\(kind.marker)` has nothing after it to convert.")
        }
        guard !unit.isEmpty else {
            throw UnsupportedInput(reason: "The \(kind.name) is empty.")
        }
        guard !containsScript(unit) else {
            throw UnsupportedInput(
                reason: "Nested superscripts and subscripts have no Unicode form.")
        }

        let inner = try Renderer.render(unit)
        for character in inner.text {
            guard let mapped = kind.table[character] else {
                throw UnsupportedInput(
                    reason: "There is no Unicode \(kind.name) for \u{201C}\(character)\u{201D}.")
            }
            out.text.append(mapped)
        }
        out.fallbacks += inner.fallbacks
    }

    // MARK: Commands

    private mutating func emit(command name: String) throws {
        switch name {
        case "frac", "dfrac", "tfrac":
            return try emitFraction(name)
        case "sqrt":
            return try emitRoot()
        case "binom", "dbinom", "tbinom":
            return try emitBinomial(name)
        case "text", "textrm", "mathrm", "operatorname":
            return try emitVerbatimGroup(name)
        case "mathbb":
            return try emitBlackboardBold()
        case "left", "right":
            // Delimiter sizing only. The delimiter itself is the next token.
            return
        case "begin", "end":
            return try rejectEnvironment()
        default:
            break
        }

        if let text = TextOperators.operators[name] {
            out.text += text
            return
        }
        if let reason = UnsupportedCommands.reasons[name] {
            throw UnsupportedInput(reason: reason)
        }
        if let symbol = SymbolTable.symbols[name] {
            out.text += symbol
            return
        }
        throw UnsupportedInput(reason: "Unknown command \\\(name).")
    }

    private mutating func emit(controlSymbol character: Character) throws {
        if let literal = UnsupportedCommands.escapedLiterals[character] {
            out.text.append(literal)
            return
        }
        if let reason = UnsupportedCommands.symbolReasons[character] {
            throw UnsupportedInput(reason: reason)
        }
        throw UnsupportedInput(reason: "Unknown command \\\(character).")
    }

    // MARK: Fallback constructions

    private mutating func emitFraction(_ name: String) throws {
        guard let numerator = nextUnit(), let denominator = nextUnit() else {
            throw UnsupportedInput(
                reason: "\\\(name) needs two arguments, for example \\\(name){a}{b}.")
        }
        let top = try Renderer.render(numerator)
        let bottom = try Renderer.render(denominator)
        guard !top.text.isEmpty, !bottom.text.isEmpty else {
            throw UnsupportedInput(reason: "\\\(name) has an empty argument.")
        }
        // A fraction whose own arguments already needed an approximation
        // cannot be represented exactly, so those go straight to the linear
        // form rather than dressing up a fallback as a real fraction.
        if top.fallbacks.isEmpty, bottom.fallbacks.isEmpty {
            // Best: a single precomposed character.
            if let exact = ScriptTables.vulgarFractions["\(top.text)/\(bottom.text)"] {
                out.text += exact
                return
            }
            // Next best: superscript numerator, fraction slash, subscript
            // denominator. This composes any fraction whose digits and letters
            // both have script forms, so 10/17 works even though no single
            // character for it exists.
            if worthComposing(numerator: top.text, denominator: bottom.text),
               let composed = composedFraction(numerator: top.text, denominator: bottom.text) {
                out.text += composed
                return
            }
        }

        out.text += mathematical(parenthesised(top.text))
            + String(divisionSlash)
            + mathematical(parenthesised(bottom.text))
        out.fallbacks += top.fallbacks + bottom.fallbacks
        out.fallbacks.append(
            "A fraction cannot be stacked in plain text, so it was written on one line with a slash.")
    }

    /// Whether a composed fraction would still be readable.
    ///
    /// Script characters are small, and superscript `x` against subscript `x`
    /// is close to indistinguishable at text size. Digits stay legible at any
    /// length, so `10/17` composes; anything longer than a couple of characters
    /// with letters in it reads better on one line.
    private func worthComposing(numerator: String, denominator: String) -> Bool {
        let bothNumeric = numerator.allSatisfy(\.isNumber) && denominator.allSatisfy(\.isNumber)
        let bothShort = numerator.count <= 2 && denominator.count <= 2
        return bothNumeric || bothShort
    }

    /// Builds a diagonal fraction out of existing script characters.
    ///
    /// Returns nil when any character lacks the form it needs — the subscript
    /// alphabet is missing `b c d f g q w y z`, so `\frac{a}{b}` cannot be
    /// composed and falls back to `a/b` instead.
    private func composedFraction(numerator: String, denominator: String) -> String? {
        var result = ""
        for character in numerator {
            guard let raised = ScriptTables.superscripts[character] else { return nil }
            result.append(raised)
        }
        result.append(ScriptTables.fractionSlash)
        for character in denominator {
            guard let lowered = ScriptTables.subscripts[character] else { return nil }
            result.append(lowered)
        }
        return result
    }

    private mutating func emitRoot() throws {
        var degree = 2
        var degreeText = "2"

        // Optional [n]. `[` and `]` are ordinary characters everywhere else,
        // so the bracket group is only recognised here, immediately after \sqrt.
        if index < tokens.count, tokens[index] == .character("[") {
            var scan = index + 1
            var inner: [Token] = []
            while scan < tokens.count, tokens[scan] != .character("]") {
                inner.append(tokens[scan])
                scan += 1
            }
            guard scan < tokens.count else {
                throw UnsupportedInput(reason: "\\sqrt has a `[` that is never closed.")
            }
            index = scan + 1
            degreeText = try Renderer.render(inner).text

            // An index that is missing or not a root produced honest-looking
            // nonsense: `\\sqrt[]{8}` came out as `8^(1/)` and `\\sqrt[0]{8}` as
            // `8^(1/0)`. A letter index is fine and common, `\\sqrt[n]{x}` reads
            // perfectly well as a fractional power; only a number below two is
            // not a root at all.
            guard !degreeText.isEmpty else {
                throw UnsupportedInput(
                    reason: "\\sqrt has an empty index, for example \\sqrt[3]{8}.")
            }
            if let written = Int(degreeText), written < 2 {
                throw UnsupportedInput(
                    reason: "A root needs an index of at least 2, so \\sqrt[\(written)] is not one.")
            }
            degree = Int(degreeText) ?? -1
        }

        guard let argument = nextUnit() else {
            throw UnsupportedInput(reason: "\\sqrt needs an argument, for example \\sqrt{2}.")
        }
        let radicand = try Renderer.render(argument)
        guard !radicand.text.isEmpty else {
            throw UnsupportedInput(reason: "\\sqrt has an empty argument.")
        }
        out.fallbacks += radicand.fallbacks

        if let radical = ScriptTables.radicals[degree] {
            out.text += String(radical) + mathematical(parenthesised(radicand.text))
            out.fallbacks.append(
                "A radical sign cannot extend over what is under it, so the root was written as \(radical)(\u{2026}).")
        } else {
            out.text += mathematical(parenthesised(radicand.text)) + "^(1/" + degreeText + ")"
            out.fallbacks.append(
                "There is no Unicode radical sign for an index of \(degreeText), so the root was written as a fractional power.")
        }
    }

    private mutating func emitBinomial(_ name: String) throws {
        guard let upper = nextUnit(), let lower = nextUnit() else {
            throw UnsupportedInput(
                reason: "\\\(name) needs two arguments, for example \\\(name){n}{k}.")
        }
        let n = try Renderer.render(upper)
        let k = try Renderer.render(lower)
        guard !n.text.isEmpty, !k.text.isEmpty else {
            throw UnsupportedInput(reason: "\\\(name) has an empty argument.")
        }
        out.text += "C(\(mathematical(n.text)), \(mathematical(k.text)))"
        out.fallbacks += n.fallbacks + k.fallbacks
        out.fallbacks.append(
            "A binomial coefficient cannot be stacked in plain text, so it was written as C(n, k).")
    }

    // MARK: Passthrough constructions

    private mutating func emitVerbatimGroup(_ name: String) throws {
        guard let unit = nextUnit() else {
            throw UnsupportedInput(reason: "\\\(name) needs an argument.")
        }
        out.append(try Renderer.render(unit))
    }

    private mutating func emitBlackboardBold() throws {
        guard let unit = nextUnit() else {
            throw UnsupportedInput(reason: "\\mathbb needs a letter, for example \\mathbb{R}.")
        }
        let letter = try Renderer.render(unit).text
        guard letter.count == 1, let symbol = SymbolTable.symbols[letter] else {
            throw UnsupportedInput(
                reason: "There is no double-struck Unicode letter for \u{201C}\(letter)\u{201D}.")
        }
        out.text += symbol
    }

    private mutating func rejectEnvironment() throws {
        guard let unit = nextUnit(), let name = try? Renderer.render(unit).text, !name.isEmpty else {
            throw UnsupportedInput(
                reason: "LaTeX environments need two-dimensional layout, which has no inline Unicode form.")
        }
        throw UnsupportedInput(
            reason: "The \(name) environment needs two-dimensional layout, which has no inline Unicode form.")
    }
}

// MARK: - Helpers

/// U+2215, the mathematical division operator, rather than the ASCII solidus.
private let divisionSlash: Character = "\u{2215}"

/// Replaces the ASCII hyphen with U+2212 MINUS SIGN.
///
/// A hyphen is not a minus: it is shorter, sits lower, and reads as a word
/// break. Only linear maths goes through here — composed fractions and scripts
/// use their own precomposed minus characters, and `\text{}` keeps its hyphens
/// so "well-known" is not mangled.
private func mathematical(_ text: String) -> String {
    String(text.map { $0 == "-" ? "\u{2212}" : $0 })
}

/// Wraps in parentheses unless it is a single character, so `\frac{1}{2}`
/// gives `½` while `\frac{x+1}{y-2}` gives `(x+1)∕(y−2)`.
private func parenthesised(_ text: String) -> String {
    text.count == 1 ? text : "(" + text + ")"
}

private func containsScript(_ tokens: [Token]) -> Bool {
    tokens.contains { token in
        switch token {
        case .sup, .sub:        return true
        case .group(let inner): return containsScript(inner)
        default:                return false
        }
    }
}

private func deduplicated(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { seen.insert($0).inserted }
}
