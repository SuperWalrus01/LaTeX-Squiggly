// Replays every fragment the Swift engine was asked about and checks that the
// Android engine answers identically: same text, same reason, same delete
// count, same decision to stay silent. The same checks as
// chrome/test/conformance.mjs, against the same conformance/reference.json.
//
// Run:  gradle -p android :engine:conformance

package io.github.superwalrus01.squiggly.engine

import java.io.File
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val path = args.firstOrNull() ?: "../conformance/reference.json"
    @Suppress("UNCHECKED_CAST")
    val records = Json.parse(File(path).readText()) as List<Map<String, Any?>>

    val failures = ArrayList<String>()
    var checks = 0
    fun show(text: Any?) = if (text == null) "(none)" else "[$text]"

    for (record in records) {
        val input = record["input"] as String

        checks += 1
        @Suppress("UNCHECKED_CAST")
        val expected = record["engine"] as Map<String, Any?>
        val engine = Engine.convert(input)
        val kind = when (engine) {
            is ConversionResult.Converted -> "converted"
            is ConversionResult.Fallback -> "fallback"
            is ConversionResult.Unsupported -> "unsupported"
        }
        val reason = when (engine) {
            is ConversionResult.Fallback -> engine.reason
            is ConversionResult.Unsupported -> engine.reason
            is ConversionResult.Converted -> null
        }
        if (kind != expected["kind"] || engine.textOrNull != expected["text"] || reason != expected["reason"]) {
            failures.add("  engine ${show(input)}\n" +
                "    swift : ${expected["kind"]} text=${show(expected["text"])} reason=${show(expected["reason"])}\n" +
                "    kotlin: $kind text=${show(engine.textOrNull)} reason=${show(reason)}")
        }

        checks += 1
        @Suppress("UNCHECKED_CAST")
        val want = record["trigger"] as Map<String, Any?>
        val wanted = when (want["kind"]) {
            "replace" -> "replace delete=${(want["deleteCount"] as Number).toInt()} " +
                "insert=${show(want["insert"])} notice=${show(want["notice"])}"
            "refuse" -> "refuse source=${show(want["source"])} reason=${show(want["reason"])}"
            else -> "none"
        }
        val trigger = Engine.outcome(input, ' ')
        val got = when (trigger) {
            is TriggerOutcome.Replace ->
                "replace delete=${trigger.deleteCount} insert=${show(trigger.insert)} notice=${show(trigger.notice)}"
            is TriggerOutcome.Refuse -> "refuse source=${show(trigger.source)} reason=${show(trigger.reason)}"
            TriggerOutcome.None -> "none"
        }
        if (got != wanted) {
            failures.add("  trigger ${show(input)}\n    swift : $wanted\n    kotlin: $got")
        }
        // The keyboard deletes by comparing `source` against the text before
        // the caret, so it has to be exactly the text the delete count
        // describes, ending the input.
        if (trigger is TriggerOutcome.Replace && !input.endsWith(trigger.source)) {
            failures.add("  source ${show(input)} does not end with ${show(trigger.source)}")
        }
    }

    val engineChecks = checks
    checks += selectionChecks(failures)

    if (failures.isEmpty()) {
        println("PASS  engine     $engineChecks checks over ${records.size} fragments,")
        println("                 every answer identical to the Swift engine")
        println("PASS  selection  ${checks - engineChecks} checks on converting selected text")
        println("      $checks checks passed.")
    } else {
        failures.take(40).forEach(::println)
        if (failures.size > 40) println("... and ${failures.size - 40} more")
        println("FAIL  ${failures.size} of $checks checks disagree")
        exitProcess(1)
    }
}

/** Just enough JSON to read the reference, so the runner needs no library. */
private object Json {
    fun parse(text: String): Any? = Parser(text).run { value().also { space(); require(i == s.length) } }

    private class Parser(val s: String) {
        var i = 0

        fun space() {
            while (i < s.length && s[i].isWhitespace()) i++
        }

        fun value(): Any? {
            space()
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> array()
                '"' -> string()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> if (c == '-' || c.isDigit()) number() else error("unexpected $c at $i")
            }
        }

        fun literal(word: String, value: Any?): Any? {
            require(s.startsWith(word, i)) { "expected $word at $i" }
            i += word.length
            return value
        }

        fun number(): Number {
            val start = i
            while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
            val text = s.substring(start, i)
            return text.toLongOrNull() ?: text.toDouble()
        }

        fun obj(): Map<String, Any?> {
            val out = LinkedHashMap<String, Any?>()
            i++
            space()
            if (s[i] == '}') { i++; return out }
            while (true) {
                space()
                val key = string()
                space()
                require(s[i++] == ':')
                out[key] = value()
                space()
                if (s[i++] == '}') return out
            }
        }

        fun array(): List<Any?> {
            val out = ArrayList<Any?>()
            i++
            space()
            if (s[i] == ']') { i++; return out }
            while (true) {
                out.add(value())
                space()
                if (s[i++] == ']') return out
            }
        }

        fun string(): String {
            require(s[i++] == '"')
            val out = StringBuilder()
            while (true) {
                when (val c = s[i++]) {
                    '"' -> return out.toString()
                    '\\' -> when (val e = s[i++]) {
                        'n' -> out.append('\n')
                        't' -> out.append('\t')
                        'r' -> out.append('\r')
                        'b' -> out.append('\b')
                        'f' -> out.append('\u000c')
                        'u' -> { out.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                        else -> out.append(e)
                    }
                    else -> out.append(c)
                }
            }
        }
    }
}
