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

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(0)
}

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
