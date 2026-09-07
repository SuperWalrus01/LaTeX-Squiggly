import Foundation
import InputTracking
import LaTeXUnicode

// A thin front end on the Phase 0 engine, for trying conversions by hand.
// No system APIs — this is a development tool, not the app.
//
//   latex-squiggly '\int_5^6'      convert one fragment
//   latex-squiggly                 interactive, one fragment per line
//   echo '\alpha' | latex-squiggly read fragments from a pipe
//
// stdout carries only the replacement text so the tool composes; reasons go to
// stderr. Exit status answers "did I get something I can paste?" — 0 for
// converted and fallback, 1 for unsupported.

let usage = """
usage: latex-squiggly [-c|--codepoints] [-a|--app-only] [fragment ...]

  latex-squiggly '\\int_5^6'        convert one fragment
  latex-squiggly                    interactive, one fragment per line
  echo '\\alpha' | latex-squiggly   read fragments from a pipe

  -c, --codepoints  also print the U+ value of every character produced
  -a, --app-only    report what the app would do and nothing more: a
                    fragment the app would not fire on is "left alone"
                    rather than run through the engine anyway

Replacement text goes to stdout, explanations to stderr.
Exit status: 0 converted or fallback, 1 unsupported, 2 left alone.
"""

func warn(_ message: String) {
    // stderr is unbuffered and stdout is not, so without this the explanation
    // overtakes the text it explains.
    fflush(stdout)
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func codepoints(of text: String) -> String {
    text.unicodeScalars
        .map { String(format: "U+%04X", $0.value) }
        .joined(separator: " ")
}

/// - Parameter labelled: true in the interactive prompt, where readability
///   matters more than composability.
/// What the app would do, not just what the engine would do.
///
/// The `$...$` rule lives in the trigger layer, so calling `convert` directly
/// would report `$x²$` for something the app turns into `x²`. A tool for trying
/// things out has to agree with the thing it is standing in for.
/// - Returns: nil when the app would not fire on this at all, which only
///   `--app-only` distinguishes; see the `.none` case below.
func appResult(for input: String, appOnly: Bool) -> ConversionResult? {
    switch TriggerDetector.outcome(buffer: input, terminator: " ") {
    case .replace(let replacement):
        // Drop the terminator the app types back.
        let text = String(replacement.insert.dropLast())
        if let notice = replacement.notice { return .fallback(text, reason: notice) }
        return .converted(text)
    case .refuse(_, let reason):
        return .unsupported(reason: reason)
    case .none:
        // Not a trigger the app would fire on. By default show the raw engine
        // result anyway — trying `\frac12` without typing the space around it
        // is the whole point of a tool for trying things by hand. Under
        // --app-only, say so instead: `x^2` converts here and does nothing in
        // the app, and anything quoting this tool as evidence of what the app
        // does needs to be able to tell those apart.
        return appOnly ? nil : convert(input)
    }
}

func report(_ input: String, labelled: Bool, showCodepoints: Bool,
            appOnly: Bool = false) -> Int32 {
    guard let result = appResult(for: input, appOnly: appOnly) else {
        labelled ? print("  left alone") : warn("left alone")
        return 2
    }

    if let text = result.text {
        print(labelled ? "  \(text)" : text)
        if showCodepoints, !text.isEmpty {
            let line = "  \(codepoints(of: text))"
            labelled ? print(line) : warn(line.trimmingCharacters(in: .whitespaces))
        }
    }

    switch result {
    case .converted:
        return 0
    case .fallback(_, let reason):
        labelled ? print("  fallback: \(reason)") : warn("fallback: \(reason)")
        return 0
    case .unsupported(let reason):
        labelled ? print("  unsupported: \(reason)") : warn("unsupported: \(reason)")
        return 1
    }
}

/// Writes every table the engine holds, as JSON, for the C# port's generator.
///
/// Undocumented in `usage` because it is a build step, not something to run by
/// hand. Dumping from the built binary rather than parsing the Swift source is
/// what stops the Windows tables from drifting: they are generated from the
/// tables this engine actually uses, so a symbol added here cannot be missing
/// there.
func dumpTables() -> Never {
    let payload: [String: Any] = [
        "entries": SymbolTable.entries.map {
            ["command": $0.command, "glyph": $0.glyph,
             "unicodeName": $0.unicodeName, "category": $0.category]
        },
        "superscripts": Dictionary(uniqueKeysWithValues:
            ScriptTables.superscripts.map { (String($0.key), String($0.value)) }),
        "subscripts": Dictionary(uniqueKeysWithValues:
            ScriptTables.subscripts.map { (String($0.key), String($0.value)) }),
        "radicals": Dictionary(uniqueKeysWithValues:
            ScriptTables.radicals.map { (String($0.key), String($0.value)) }),
        "vulgarFractions": ScriptTables.vulgarFractions,
        "fractionSlash": String(ScriptTables.fractionSlash),
        "operators": TextOperators.operators,
        "unsupportedReasons": UnsupportedCommands.reasons,
        "escapedLiterals": Dictionary(uniqueKeysWithValues:
            UnsupportedCommands.escapedLiterals.map { (String($0.key), String($0.value)) }),
        "symbolReasons": Dictionary(uniqueKeysWithValues:
            UnsupportedCommands.symbolReasons.map { (String($0.key), $0.value) }),
    ]
    guard let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) else {
        warn("could not serialise the tables")
        exit(1)
    }
    FileHandle.standardOutput.write(data)
    print("")
    exit(0)
}

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(0)
}

if arguments.contains("--dump-tables") { dumpTables() }

/// Reads one fragment per line and prints, as JSON, exactly what both layers
/// decided about it.
///
/// This is the reference the C# port is checked against. The Windows build
/// cannot be run on this machine, so the only way to know its engine agrees
/// with this one is to ask both the same few thousand questions and diff the
/// answers. Undocumented in `usage` for the same reason as --dump-tables: it is
/// a build step, not a thing to type.
func runConformance() -> Never {
    var records: [[String: Any]] = []
    while let line = readLine(strippingNewline: true) {
        let engine = convert(line)
        var record: [String: Any] = ["input": line]

        switch engine {
        case .converted(let text):
            record["engine"] = ["kind": "converted", "text": text]
        case .fallback(let text, let reason):
            record["engine"] = ["kind": "fallback", "text": text, "reason": reason]
        case .unsupported(let reason):
            record["engine"] = ["kind": "unsupported", "reason": reason]
        }

        switch TriggerDetector.outcome(buffer: line, terminator: " ") {
        case .none:
            record["trigger"] = ["kind": "none"]
        case .replace(let r):
            var replace: [String: Any] = ["kind": "replace",
                                          "deleteCount": r.deleteCount,
                                          "insert": r.insert]
            if let notice = r.notice { replace["notice"] = notice }
            record["trigger"] = replace
        case .refuse(let source, let reason):
            record["trigger"] = ["kind": "refuse", "source": source, "reason": reason]
        }
        records.append(record)
    }
    guard let data = try? JSONSerialization.data(
        withJSONObject: records, options: [.sortedKeys]) else {
        warn("could not serialise the results")
        exit(1)
    }
    FileHandle.standardOutput.write(data)
    exit(0)
}

if arguments.contains("--conformance") { runConformance() }

let showCodepoints = arguments.contains("-c") || arguments.contains("--codepoints")
arguments.removeAll { $0 == "-c" || $0 == "--codepoints" }

let appOnly = arguments.contains("-a") || arguments.contains("--app-only")
arguments.removeAll { $0 == "-a" || $0 == "--app-only" }

if !arguments.isEmpty {
    exit(report(arguments.joined(separator: " "), labelled: false,
                showCodepoints: showCodepoints, appOnly: appOnly))
}

if isatty(FileHandle.standardInput.fileDescriptor) != 0 {
    print("LaTeX \u{2192} Unicode. Enter a fragment, or Ctrl-D to quit.")
    while true {
        print("> ", terminator: "")
        fflush(stdout)
        guard let line = readLine() else {
            print("")
            break
        }
        guard !line.isEmpty else { continue }
        _ = report(line, labelled: true, showCodepoints: showCodepoints, appOnly: appOnly)
    }
} else {
    var status: Int32 = 0
    while let line = readLine() {
        guard !line.isEmpty else { continue }
        if report(line, labelled: false, showCodepoints: showCodepoints,
                  appOnly: appOnly) != 0 { status = 1 }
    }
    exit(status)
}
