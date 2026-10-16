// Text the user selected in another app, from the "Convert LaTeX" and
// "Render LaTeX" entries Android puts in the selection menu. Unlike typing,
// nothing here guesses: the user chose this text and asked for it.

package io.github.superwalrus01.squiggly.engine

object Selection {

    private val pairs = listOf("$$" to "$$", "\\[" to "\\]", "\\(" to "\\)", "$" to "$")

    /**
     * Takes the maths delimiters off a selection: $...$, $$...$$, \(...\) and
     * \[...\]. Only a matching pair around the whole selection is removed, so
     * "costs $5 and $6" stays as it is. The same rule as the extension's
     * renderer/delimiters.js.
     */
    fun stripDelimiters(text: String): String {
        val trimmed = text.trim()
        for ((open, close) in pairs) {
            if (trimmed.length < open.length + close.length) continue
            if (!trimmed.startsWith(open) || !trimmed.endsWith(close)) continue
            val inner = trimmed.substring(open.length, trimmed.length - close.length)
            // $a$ and $b$ starts and ends with $ but is two pieces of maths.
            if (close in inner) continue
            return inner.trim()
        }
        return trimmed
    }

    /**
     * Converts a selection, all or nothing, as the engine does.
     *
     * Delimited maths around the whole selection is unwrapped first. A
     * selection with `$...$` spans inside prose, "where $x^2$ is", converts
     * each span and leaves the prose alone, since the dollars say exactly which
     * parts are maths. Anything else is converted whole, which leaves plain
     * words as they are and turns each command into its symbol.
     *
     * Whitespace around the selection is kept, so replacing it does not glue
     * words together.
     */
    fun convert(selection: String): ConversionResult {
        val leading = selection.takeWhile { it.isWhitespace() }
        val trailing = selection.takeLastWhile { it.isWhitespace() }
        if (leading.length == selection.length) return ConversionResult.Unsupported("There is nothing to convert.")
        val stripped = stripDelimiters(selection)

        val result = if (stripped == selection.trim() && countDollars(stripped) >= 2) {
            convertSpans(stripped)
        } else {
            Engine.convert(stripped)
        }
        return when (result) {
            is ConversionResult.Converted -> ConversionResult.Converted(leading + result.text + trailing)
            is ConversionResult.Fallback -> ConversionResult.Fallback(leading + result.text + trailing, result.reason)
            is ConversionResult.Unsupported -> result
        }
    }

    // A dollar written \$ is a literal, not a delimiter.
    private fun countDollars(text: String): Int =
        text.indices.count { text[it] == '$' && (it == 0 || text[it - 1] != '\\') }

    private fun convertSpans(text: String): ConversionResult {
        val out = StringBuilder()
        val reasons = ArrayList<String>()
        var index = 0
        while (index < text.length) {
            val open = nextDollar(text, index)
            if (open < 0) break
            val close = nextDollar(text, open + 1)
            // An odd dollar at the end is left as it is, like the prose.
            if (close < 0) break
            out.append(text, index, open)
            val content = text.substring(open + 1, close)
            // As when typing: only a span with a backslash, caret or
            // underscore in it is maths, so "costs $5 and $6" keeps its dollars.
            if (content.none { it == '\\' || it == '^' || it == '_' }) {
                out.append(text, open, close + 1)
                index = close + 1
                continue
            }
            when (val span = Engine.convert(content)) {
                is ConversionResult.Converted -> out.append(span.text)
                is ConversionResult.Fallback -> { out.append(span.text); reasons.add(span.reason) }
                is ConversionResult.Unsupported -> return ConversionResult.Unsupported("In \$$content\$: ${span.reason}")
            }
            index = close + 1
        }
        out.append(text, index, text.length)
        return if (reasons.isEmpty()) {
            ConversionResult.Converted(out.toString())
        } else {
            ConversionResult.Fallback(out.toString(), reasons.distinct().joinToString(" "))
        }
    }

    private fun nextDollar(text: String, from: Int): Int {
        var i = from
        while (i < text.length) {
            if (text[i] == '$' && (i == 0 || text[i - 1] != '\\')) return i
            i += 1
        }
        return -1
    }
}
