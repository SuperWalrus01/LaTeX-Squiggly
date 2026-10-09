import Foundation

/// Finds the LaTeX the user means to render, at the end of the text before
/// the cursor. Pure so it can be tested off the device.
enum MathSource {

    /// The trailing `$$...$$` or `$...$` span if there is one, else the
    /// equation the text ends with: its space-separated pieces back to the
    /// last ordinary word on the line, so `so x^2 + \alpha = 1` gives
    /// `x^2 + \alpha = 1`. Spaces inside braces never split it, so
    /// `\frac{-b \pm 1}{2}` comes out whole.
    static func trailing(in before: String) -> String? {
        let text = before.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        for delimiter in ["$$", "$"] where text.hasSuffix(delimiter) {
            let body = text.dropLast(delimiter.count)
            if let open = body.range(of: delimiter, options: .backwards) {
                return String(text[open.lowerBound...])
            }
        }

        let line = text[(text.lastIndex(where: \.isNewline).map(text.index(after:)) ?? text.startIndex)...]
        var start = line.endIndex
        for piece in pieces(of: line).reversed() {
            if isWord(piece) { break }
            start = piece.startIndex
        }
        let run = line[start...].trimmingCharacters(in: .whitespaces)
        return run.isEmpty ? nil : run
    }

    /// `line` split at spaces outside braces.
    private static func pieces(of line: Substring) -> [Substring] {
        var pieces: [Substring] = []
        var depth = 0
        var start: Substring.Index?
        for index in line.indices {
            let character = line[index]
            if character.isWhitespace && depth <= 0 {
                if let begun = start { pieces.append(line[begun..<index]) }
                start = nil
                continue
            }
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if start == nil { start = index }
        }
        if let begun = start { pieces.append(line[begun...]) }
        return pieces
    }

    /// An ordinary word, which ends an equation: two or more letters and
    /// nothing else, give or take punctuation after it. Not `dx`, which
    /// ends integrals.
    private static func isWord(_ piece: Substring) -> Bool {
        let core = piece.reversed().drop(while: { ".,;:!?".contains($0) }).reversed()
        guard core.count >= 2, core.allSatisfy({ $0.isLetter }) else { return false }
        return !(core.count == 2 && core.first == "d")
    }

    /// The math around the cursor: the trailing span of `before`, completed
    /// with whatever closes it just after the cursor. Templates leave the
    /// cursor inside braces, so `x^{2|}` has to render as `x^{2}` before the
    /// user ever leaves them.
    static func around(before: String, after: String) -> String? {
        // Inside an unfinished `$...`: all of it, to its closing delimiter
        // after the cursor, or closed here if there is none yet.
        if let open = openSpan(in: before) {
            var tail = open.close
            if let close = after.range(of: open.close) {
                let rest = String(after[..<close.upperBound])
                if !rest.contains(where: \.isNewline) { tail = rest }
            }
            return String(before[open.start...]) + tail
        }

        var depth = openBraces(in: before)
        var closing = ""
        for character in after {
            if character.isNewline || (character.isWhitespace && depth == 0) { break }
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            closing.append(character)
            if depth < 0 { break }
        }
        return trailing(in: before + closing)
    }

    /// The math `before` ends inside: where its opening `$`, `$$`, `\(` or
    /// `\[` is, and what closes it. Nil outside math. `\$` is a dollar sign.
    static func openSpan(in before: String) -> (start: String.Index, close: String)? {
        let delimiters = [("$$", "$$"), ("$", "$"), ("\\(", "\\)"), ("\\[", "\\]")]
        var open: (start: String.Index, close: String)?
        var index = before.startIndex
        while index < before.endIndex {
            let rest = before[index...]
            var step = 1
            if rest.hasPrefix("\\$") {
                step = 2
            } else if let current = open {
                if rest.hasPrefix(current.close) {
                    open = nil
                    step = current.close.count
                }
            } else if let (opener, closer) = delimiters.first(where: { rest.hasPrefix($0.0) }) {
                open = (index, closer)
                step = opener.count
            }
            index = before.index(index, offsetBy: step)
        }
        return open
    }

    /// Braces opened in `before` and not yet closed.
    static func openBraces(in before: String) -> Int {
        var depth = 0
        for character in before {
            if character == "{" { depth += 1 }
            if character == "}" { depth = max(0, depth - 1) }
        }
        return depth
    }
}
