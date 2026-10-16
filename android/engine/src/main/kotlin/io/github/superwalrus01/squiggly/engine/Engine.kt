// The conversion engine and the trigger rules, ported from the Chrome
// extension's engine, which is itself checked against the Swift engine.
// Conformance.kt replays the same 2,030 fragments against this file, so a
// difference from the Mac app shows up there rather than in somebody's email.
//
// Plain Kotlin with no Android imports, so it builds and is checked on any JVM.

package io.github.superwalrus01.squiggly.engine

import java.math.BigInteger
import java.text.BreakIterator

/** What the engine made of a piece of LaTeX. All or nothing: never half converted. */
sealed class ConversionResult {
    data class Converted(val text: String) : ConversionResult()
    /** Converted, but only approximately; [reason] says how. */
    data class Fallback(val text: String, val reason: String) : ConversionResult()
    data class Unsupported(val reason: String) : ConversionResult()

    val textOrNull: String?
        get() = when (this) {
            is Converted -> text
            is Fallback -> text
            is Unsupported -> null
        }
}

/** What to do when a terminator is typed. */
sealed class TriggerOutcome {
    object None : TriggerOutcome()

    /**
     * Replace [source], the exact typed text ending at the caret, with [insert],
     * which carries the terminator back. [deleteCount] counts characters as
     * Swift does; an editor deleting UTF-16 units should use `source.length`.
     */
    data class Replace(
        val source: String,
        val deleteCount: Int,
        val insert: String,
        val notice: String?,
    ) : TriggerOutcome()

    /** A real LaTeX attempt with no honest Unicode form: leave it and say why. */
    data class Refuse(val source: String, val reason: String) : TriggerOutcome()
}

object Engine {

    /** Every symbol the engine knows, in the order of the coverage table. */
    val symbolEntries: List<SymbolEntry> get() = Tables.entries

    private val symbols: Map<String, String> = Tables.entries.associate { it.command to it.glyph }

    // MARK: Characters

    // Counting characters the way Swift does. LaTeX source is ASCII, where a
    // code unit is a character, but the engine's output is not: the
    // double-struck alphabet lives outside the basic plane, so \mathbb{X} is one
    // character and two code units.
    private fun isAscii(text: String) = text.all { it.code < 0x80 }

    fun characters(text: String): List<String> {
        if (isAscii(text)) return text.map { it.toString() }
        val iterator = BreakIterator.getCharacterInstance()
        iterator.setText(text)
        val out = ArrayList<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            out.add(text.substring(start, end))
            start = end
            end = iterator.next()
        }
        return out
    }

    fun characterCount(text: String): Int = if (isAscii(text)) text.length else characters(text).size

    private fun isAsciiLetter(ch: Char) = ch in 'A'..'Z' || ch in 'a'..'z'

    // JavaScript's \s, which the extension's engine uses and which agrees with
    // Swift on everything the conformance corpus holds.
    private fun isWhitespace(ch: Char): Boolean = when (ch) {
        '\t', '\n', '\u000b', '\u000c', '\r', ' ', '\u00a0', '\u1680',
        '\u2028', '\u2029', '\u202f', '\u205f', '\u3000', '\ufeff' -> true
        else -> ch in '\u2000'..'\u200a'
    }

    // MARK: Tokenizer

    private sealed class Token {
        data class Command(val name: String) : Token()
        data class ControlSymbol(val symbol: Char) : Token()
        data class Group(val inner: List<Token>) : Token()
        object Sup : Token()
        object Sub : Token()
        data class Character(val value: Char) : Token()
    }

    private class Refusal(message: String) : Exception(message)

    private const val UNBALANCED_BRACE = "Unbalanced braces \u2014 a `{` was never closed."
    private const val UNEXPECTED_CLOSING_BRACE = "Unbalanced braces \u2014 a `}` has no matching `{`."
    private const val DANGLING_BACKSLASH = "The input ends with a lone backslash."

    // Longest match: a command name is the longest run of ASCII letters, which is
    // what keeps \int from being read as \in then t. The terminator is kept as an
    // ordinary token rather than swallowed, so "\alpha " keeps its space.
    private fun tokenize(input: String): List<Token> {
        val state = intArrayOf(0)
        val tokens = scan(input, state, 0)
        // A `}` at depth 0 stops the scan; anything left over is unmatched.
        if (state[0] != input.length) throw Refusal(UNEXPECTED_CLOSING_BRACE)
        return tokens
    }

    private fun scan(c: String, state: IntArray, depth: Int): List<Token> {
        val output = ArrayList<Token>()
        while (state[0] < c.length) {
            val ch = c[state[0]]
            when (ch) {
                '\\' -> {
                    state[0] += 1
                    if (state[0] >= c.length) throw Refusal(DANGLING_BACKSLASH)
                    if (isAsciiLetter(c[state[0]])) {
                        val start = state[0]
                        while (state[0] < c.length && isAsciiLetter(c[state[0]])) state[0] += 1
                        output.add(Token.Command(c.substring(start, state[0])))
                    } else {
                        output.add(Token.ControlSymbol(c[state[0]]))
                        state[0] += 1
                    }
                }
                '{' -> {
                    state[0] += 1
                    val inner = scan(c, state, depth + 1)
                    if (state[0] >= c.length || c[state[0]] != '}') throw Refusal(UNBALANCED_BRACE)
                    state[0] += 1
                    output.add(Token.Group(inner))
                }
                // Let the caller consume it; at depth 0 tokenize rejects it.
                '}' -> return output
                '^' -> { output.add(Token.Sup); state[0] += 1 }
                '_' -> { output.add(Token.Sub); state[0] += 1 }
                else -> { output.add(Token.Character(ch)); state[0] += 1 }
            }
        }
        if (depth > 0) throw Refusal(UNBALANCED_BRACE)
        return output
    }

    // MARK: Renderer

    private const val DIVISION_SLASH = "\u2215"

    private class ScriptKind(val name: String, val marker: String, val table: Map<String, String>)

    private val superscriptKind = ScriptKind("superscript", "^", Tables.superscripts)
    private val subscriptKind = ScriptKind("subscript", "_", Tables.subscripts)

    // Replaces the hyphen with U+2212 MINUS SIGN. Only linear maths goes through
    // here, so \text{well-known} keeps its hyphen.
    private fun mathematical(text: String) = text.replace("-", "\u2212")

    private fun parenthesised(text: String) = if (characterCount(text) == 1) text else "($text)"

    private fun containsScript(tokens: List<Token>): Boolean = tokens.any {
        it is Token.Sup || it is Token.Sub || (it is Token.Group && containsScript(it.inner))
    }

    // Swift's Int(): an optional sign and ASCII digits, nothing else, and nil
    // when the value does not fit in 64 bits.
    private val swiftIntPattern = Regex("^[+-]?[0-9]+$")
    private val longMin = BigInteger.valueOf(Long.MIN_VALUE)
    private val longMax = BigInteger.valueOf(Long.MAX_VALUE)

    private fun swiftInt(text: String): Long? {
        if (!swiftIntPattern.matches(text)) return null
        val value = BigInteger(text.removePrefix("+"))
        if (value > longMax || value < longMin) return null
        return value.toLong()
    }

    private class Renderer(private val tokens: List<Token>) {
        private var index = 0
        val text = StringBuilder()
        val fallbacks = ArrayList<String>()

        companion object {
            fun render(tokens: List<Token>): Renderer = Renderer(tokens).also { it.run() }
        }

        private fun append(other: Renderer) {
            text.append(other.text)
            fallbacks.addAll(other.fallbacks)
        }

        private fun run() {
            while (index < tokens.size) {
                when (val token = tokens[index++]) {
                    is Token.Character -> text.append(token.value)
                    is Token.Group -> append(render(token.inner))
                    Token.Sup -> applyScript(superscriptKind)
                    Token.Sub -> applyScript(subscriptKind)
                    is Token.ControlSymbol -> emitControlSymbol(token.symbol)
                    is Token.Command -> emitCommand(token.name)
                }
            }
        }

        // The next argument: a braced group's contents or a single token, so
        // \frac12 and \frac{1}{2} behave the same. Whitespace before it is
        // skipped, so \mathbb R works.
        private fun nextUnit(): List<Token>? {
            while (index < tokens.size) {
                val white = tokens[index]
                if (white !is Token.Character || !isWhitespace(white.value)) break
                index += 1
            }
            if (index >= tokens.size) return null
            val token = tokens[index++]
            return if (token is Token.Group) token.inner else listOf(token)
        }

        private fun applyScript(kind: ScriptKind) {
            val unit = nextUnit() ?: throw Refusal("`${kind.marker}` has nothing after it to convert.")
            if (unit.isEmpty()) throw Refusal("The ${kind.name} is empty.")
            if (containsScript(unit)) {
                throw Refusal("Nested superscripts and subscripts have no Unicode form.")
            }
            val inner = render(unit)
            for (character in characters(inner.text.toString())) {
                val mapped = (if (character.length == 1) kind.table[character] else null)
                    ?: throw Refusal("There is no Unicode ${kind.name} for \u201c$character\u201d.")
                text.append(mapped)
            }
            fallbacks.addAll(inner.fallbacks)
        }

        private fun emitCommand(name: String) {
            when (name) {
                "frac", "dfrac", "tfrac" -> return emitFraction(name)
                "sqrt" -> return emitRoot()
                "binom", "dbinom", "tbinom" -> return emitBinomial(name)
                "text", "textrm", "mathrm", "operatorname" -> return emitVerbatimGroup(name)
                "mathbb" -> return emitBlackboardBold()
                // Delimiter sizing only. The delimiter itself is the next token.
                "left", "right" -> return
                "begin", "end" -> return rejectEnvironment()
            }
            Tables.operators[name]?.let { text.append(it); return }
            Tables.unsupportedReasons[name]?.let { throw Refusal(it) }
            symbols[name]?.let { text.append(it); return }
            throw Refusal("Unknown command \\$name.")
        }

        private fun emitControlSymbol(character: Char) {
            val key = character.toString()
            Tables.escapedLiterals[key]?.let { text.append(it); return }
            Tables.symbolReasons[key]?.let { throw Refusal(it) }
            throw Refusal("Unknown command \\$character.")
        }

        private fun emitFraction(name: String) {
            val numerator = nextUnit()
            val denominator = nextUnit()
            if (numerator == null || denominator == null) {
                throw Refusal("\\$name needs two arguments, for example \\$name{a}{b}.")
            }
            val top = render(numerator)
            val bottom = render(denominator)
            if (top.text.isEmpty() || bottom.text.isEmpty()) throw Refusal("\\$name has an empty argument.")
            val topText = top.text.toString()
            val bottomText = bottom.text.toString()

            // A fraction whose arguments already needed an approximation goes
            // straight to the linear form rather than dressing up a fallback.
            if (top.fallbacks.isEmpty() && bottom.fallbacks.isEmpty()) {
                Tables.vulgarFractions["$topText/$bottomText"]?.let { text.append(it); return }
                if (worthComposing(topText, bottomText)) {
                    composedFraction(topText, bottomText)?.let { text.append(it); return }
                }
            }

            text.append(mathematical(parenthesised(topText)))
                .append(DIVISION_SLASH)
                .append(mathematical(parenthesised(bottomText)))
            fallbacks.addAll(top.fallbacks)
            fallbacks.addAll(bottom.fallbacks)
            fallbacks.add("A fraction cannot be stacked in plain text, so it was written on one line with a slash.")
        }

        private fun emitRoot() {
            var degree = 2L
            var degreeText = "2"

            // Optional [n], recognised only immediately after \sqrt.
            val next = tokens.getOrNull(index)
            if (next is Token.Character && next.value == '[') {
                var scan = index + 1
                val inner = ArrayList<Token>()
                while (scan < tokens.size) {
                    val t = tokens[scan]
                    if (t is Token.Character && t.value == ']') break
                    inner.add(t)
                    scan += 1
                }
                if (scan >= tokens.size) throw Refusal("\\sqrt has a `[` that is never closed.")
                index = scan + 1
                degreeText = render(inner).text.toString()

                if (degreeText.isEmpty()) throw Refusal("\\sqrt has an empty index, for example \\sqrt[3]{8}.")
                val written = swiftInt(degreeText)
                if (written != null && written < 2) {
                    throw Refusal("A root needs an index of at least 2, so \\sqrt[$written] is not one.")
                }
                degree = written ?: -1
            }

            val argument = nextUnit() ?: throw Refusal("\\sqrt needs an argument, for example \\sqrt{2}.")
            val radicand = render(argument)
            if (radicand.text.isEmpty()) throw Refusal("\\sqrt has an empty argument.")
            fallbacks.addAll(radicand.fallbacks)
            val radicandText = mathematical(parenthesised(radicand.text.toString()))

            val radical = if (degree in Int.MIN_VALUE..Int.MAX_VALUE) Tables.radicals[degree.toInt()] else null
            if (radical != null) {
                text.append(radical).append(radicandText)
                fallbacks.add("A radical sign cannot extend over what is under it, so the root was written as $radical(\u2026).")
            } else {
                text.append(radicandText).append("^(1/").append(degreeText).append(")")
                fallbacks.add("There is no Unicode radical sign for an index of $degreeText, so the root was written as a fractional power.")
            }
        }

        private fun emitBinomial(name: String) {
            val upper = nextUnit()
            val lower = nextUnit()
            if (upper == null || lower == null) {
                throw Refusal("\\$name needs two arguments, for example \\$name{n}{k}.")
            }
            val n = render(upper)
            val k = render(lower)
            if (n.text.isEmpty() || k.text.isEmpty()) throw Refusal("\\$name has an empty argument.")
            text.append("C(").append(mathematical(n.text.toString())).append(", ")
                .append(mathematical(k.text.toString())).append(")")
            fallbacks.addAll(n.fallbacks)
            fallbacks.addAll(k.fallbacks)
            fallbacks.add("A binomial coefficient cannot be stacked in plain text, so it was written as C(n, k).")
        }

        private fun emitVerbatimGroup(name: String) {
            val unit = nextUnit() ?: throw Refusal("\\$name needs an argument.")
            append(render(unit))
        }

        private fun emitBlackboardBold() {
            val unit = nextUnit() ?: throw Refusal("\\mathbb needs a letter, for example \\mathbb{R}.")
            val letter = render(unit).text.toString()
            val glyph = (if (characterCount(letter) == 1) symbols[letter] else null)
                ?: throw Refusal("There is no double-struck Unicode letter for \u201c$letter\u201d.")
            text.append(glyph)
        }

        private fun rejectEnvironment() {
            val unit = nextUnit()
            val name = if (unit == null) "" else try {
                render(unit).text.toString()
            } catch (_: Refusal) {
                ""
            }
            if (name.isEmpty()) {
                throw Refusal("LaTeX environments need two-dimensional layout, which has no inline Unicode form.")
            }
            throw Refusal("The $name environment needs two-dimensional layout, which has no inline Unicode form.")
        }
    }

    // Whether a composed fraction would still be readable. Digits stay legible
    // at any length; anything else only when both parts are short. Checked per
    // code unit, as the other ports do, so a lone surrogate is never a number.
    private fun isNumber(ch: Char) = when (Character.getType(ch)) {
        Character.DECIMAL_DIGIT_NUMBER.toInt(),
        Character.LETTER_NUMBER.toInt(),
        Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }

    private fun worthComposing(numerator: String, denominator: String): Boolean {
        val bothNumeric = numerator.all(::isNumber) && denominator.all(::isNumber)
        val bothShort = characterCount(numerator) <= 2 && characterCount(denominator) <= 2
        return bothNumeric || bothShort
    }

    // A diagonal fraction built from script characters, or null when any
    // character lacks the form it needs.
    private fun composedFraction(numerator: String, denominator: String): String? {
        val result = StringBuilder()
        for (ch in numerator) result.append(Tables.superscripts[ch.toString()] ?: return null)
        result.append(Tables.FRACTION_SLASH)
        for (ch in denominator) result.append(Tables.subscripts[ch.toString()] ?: return null)
        return result.toString()
    }

    /** Converts a whole piece of LaTeX. All or nothing. */
    fun convert(latex: String): ConversionResult {
        if (latex.isEmpty()) return ConversionResult.Unsupported("There is nothing to convert.")
        return try {
            val rendered = Renderer.render(tokenize(latex))
            if (rendered.fallbacks.isEmpty()) {
                ConversionResult.Converted(rendered.text.toString())
            } else {
                ConversionResult.Fallback(rendered.text.toString(), rendered.fallbacks.distinct().joinToString(" "))
            }
        } catch (refusal: Refusal) {
            ConversionResult.Unsupported(refusal.message ?: "")
        }
    }

    // MARK: Known commands

    private val structural = setOf(
        "frac", "dfrac", "tfrac", "sqrt", "binom", "dbinom", "tbinom",
        "text", "textrm", "mathrm", "operatorname", "mathbb",
        "left", "right", "begin", "end",
    )

    private fun leadingCommandName(candidate: String): String? {
        if (candidate.firstOrNull() != '\\') return null
        val name = candidate.drop(1).takeWhile(::isAsciiLetter)
        return name.ifEmpty { null }
    }

    private fun isKnown(name: String) = name in symbols || name in Tables.operators ||
        name in Tables.unsupportedReasons || name in structural

    private fun isKnownControlSymbol(ch: Char) =
        ch.toString() in Tables.escapedLiterals || ch.toString() in Tables.symbolReasons

    /** True when the candidate opens with a command someone could have meant. */
    private fun looksIntentional(candidate: String): Boolean {
        val name = leadingCommandName(candidate) ?: return false
        return isKnown(name)
    }

    // True when every command is known and the braces balance. Reporting a
    // failure needs this: C:\path\to\file opens with \to, a real command, and
    // must still stay quiet.
    private fun isWhollyIntentional(candidate: String): Boolean {
        var index = 0
        var depth = 0
        var sawCommand = false
        while (index < candidate.length) {
            when (candidate[index]) {
                '\\' -> {
                    index += 1
                    if (index >= candidate.length) return false
                    if (isAsciiLetter(candidate[index])) {
                        val start = index
                        while (index < candidate.length && isAsciiLetter(candidate[index])) index += 1
                        if (!isKnown(candidate.substring(start, index))) return false
                    } else {
                        if (!isKnownControlSymbol(candidate[index])) return false
                        index += 1
                    }
                    sawCommand = true
                }
                '{' -> { depth += 1; index += 1 }
                '}' -> {
                    depth -= 1
                    if (depth < 0) return false
                    index += 1
                }
                else -> index += 1
            }
        }
        return sawCommand && depth == 0
    }

    // MARK: Trigger detection

    /** Keystrokes that complete a command: space and tab, never Return. */
    val terminators: Set<Char> = setOf(' ', '\t')

    // Longest $...$ span considered, so a stray dollar earlier in the sentence
    // cannot swallow half a line.
    private const val MAXIMUM_DELIMITED_LENGTH = 48

    private fun replace(source: String, text: String, notice: String?, terminator: Char) =
        TriggerOutcome.Replace(source, characterCount(source), text + terminator, notice)

    private fun fromResult(source: String, result: ConversionResult, terminator: Char): TriggerOutcome =
        when (result) {
            is ConversionResult.Converted -> replace(source, result.text, null, terminator)
            is ConversionResult.Fallback -> replace(source, result.text, result.reason, terminator)
            is ConversionResult.Unsupported -> TriggerOutcome.Refuse(source, result.reason)
        }

    // $x^2$ is something nobody types by accident, where bare x^2 is. A failure
    // here is always reported: the dollars are a statement of intent.
    private fun mathDelimited(buffer: String, terminator: Char): TriggerOutcome? {
        if (buffer.lastOrNull() != '$') return null
        val beforeClosing = buffer.dropLast(1)
        val opening = beforeClosing.lastIndexOf('$')
        if (opening < 0) return null

        val content = beforeClosing.substring(opening + 1)
        if (content.isEmpty() ||
            characterCount(content) > MAXIMUM_DELIMITED_LENGTH ||
            content.none { it == '\\' || it == '^' || it == '_' }
        ) {
            return null
        }
        return fromResult("\$$content\$", convert(content), terminator)
    }

    // Every point a candidate could begin, earliest first, within the run since
    // the last whitespace. Earliest first is what keeps \frac{\alpha}{2} whole.
    private fun candidateStarts(buffer: String): List<String> {
        var runStart = 0
        for (i in buffer.indices.reversed()) {
            if (isWhitespace(buffer[i])) { runStart = i + 1; break }
        }
        return (runStart until buffer.length).filter { buffer[it] == '\\' }.map { buffer.substring(it) }
    }

    /**
     * What to do given the text just typed and the terminator. The terminator
     * is assumed suppressed by the caller, so a replacement's `insert` carries
     * it back.
     */
    fun outcome(buffer: String, terminator: Char): TriggerOutcome {
        mathDelimited(buffer, terminator)?.let { return it }

        var refusal: TriggerOutcome? = null
        for (candidate in candidateStarts(buffer)) {
            if (characterCount(candidate) <= 1) continue
            if (!looksIntentional(candidate)) continue

            val result = convert(candidate)
            if (result !is ConversionResult.Unsupported) return fromResult(candidate, result, terminator)
            if (refusal == null && isWhollyIntentional(candidate)) {
                refusal = TriggerOutcome.Refuse(candidate, result.reason)
            }
        }
        return refusal ?: TriggerOutcome.None
    }
}
