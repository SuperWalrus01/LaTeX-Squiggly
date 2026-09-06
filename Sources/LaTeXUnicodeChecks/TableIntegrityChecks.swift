import LaTeXUnicode

/// Invariants the converter's dispatch order silently depends on. Without
/// these, adding a table entry can shadow another one with no failure.
func runTableIntegrityChecks(_ c: Checker) {

    let symbols = Set(SymbolTable.symbols.keys)
    let operators = Set(TextOperators.operators.keys)
    let refused = Set(UnsupportedCommands.reasons.keys)

    c.expect(symbols.isDisjoint(with: operators),
             "symbols/operators overlap: \(symbols.intersection(operators))")
    c.expect(symbols.isDisjoint(with: refused),
             "symbols/refused overlap: \(symbols.intersection(refused))")
    c.expect(operators.isDisjoint(with: refused),
             "operators/refused overlap: \(operators.intersection(refused))")

    // The converter intercepts these before any table lookup, so a table
    // entry with the same name would be unreachable.
    let intercepted: Set<String> = ["frac", "dfrac", "tfrac", "sqrt",
                                    "binom", "dbinom", "tbinom",
                                    "text", "textrm", "mathrm", "operatorname",
                                    "mathbb", "left", "right", "begin", "end"]
    for name in intercepted {
        c.isNil(SymbolTable.symbols[name], "\\\(name) would be unreachable")
        c.isNil(TextOperators.operators[name], "\\\(name) would be unreachable")
        c.isNil(UnsupportedCommands.reasons[name], "\\\(name) would be unreachable")
    }

    // `\mathbb{X}` resolves by looking X up in the symbol table, which is only
    // correct while every single-character key is a double-struck letter.
    let singles = Set(symbols.filter { $0.count == 1 })
    c.equal(singles, ["R", "Q", "Z", "N", "C", "H", "E", "F", "P"],
            "single-character symbol keys")

    for (command, value) in SymbolTable.symbols {
        c.expect(!value.isEmpty, "\\\(command) maps to nothing")
    }

    // Command names must be pure ASCII letters or the tokenizer can never
    // produce them.
    for command in symbols.union(operators).union(refused) {
        c.expect(command.allSatisfy { $0.isASCII && $0.isLetter },
                 "\\\(command) is unreachable from the tokenizer")
    }

    c.equal(Set(ScriptTables.superscripts.keys.filter { $0.isLetter }),
            Set("abcdefghijklmnoprstuvwxyz"), "superscript letter coverage")
    c.equal(Set(ScriptTables.subscripts.keys.filter { $0.isLetter }),
            Set("aehijklmnoprstuvx"), "subscript letter coverage")

    for digit in "0123456789" {
        c.notNil(ScriptTables.superscripts[digit], "superscript \(digit)")
        c.notNil(ScriptTables.subscripts[digit], "subscript \(digit)")
    }
}
