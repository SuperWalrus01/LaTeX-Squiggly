import Foundation

/// Finds the LaTeX the user means to render, at the end of the text before
/// the cursor. Pure so it can be tested off the device.
enum MathSource {

    /// The trailing `$$...$$` or `$...$` span if there is one, else the
    /// trailing run up to a space outside any braces, so `\frac{a}{b}` and
    /// `\frac{-b \pm 1}{2}` both come out whole.
    static func trailing(in before: String) -> String? {
        let text = before.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        for delimiter in ["$$", "$"] where text.hasSuffix(delimiter) {
            let body = text.dropLast(delimiter.count)
            if let open = body.range(of: delimiter, options: .backwards) {
                return String(text[open.lowerBound...])
            }
        }

        var depth = 0
        var start = text.endIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character.isWhitespace && depth <= 0 { break }
            if character == "}" { depth += 1 }
            if character == "{" { depth -= 1 }
            start = previous
        }
        let run = text[start...]
        return run.isEmpty ? nil : String(run)
    }

    /// The math around the cursor: the trailing span of `before`, completed
    /// with whatever closes it just after the cursor. Templates leave the
    /// cursor inside braces, so `x^{2|}` has to render as `x^{2}` before the
    /// user ever leaves them.
    static func around(before: String, after: String) -> String? {
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
