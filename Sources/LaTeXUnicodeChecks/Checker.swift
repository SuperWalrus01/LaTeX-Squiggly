import Foundation
import LaTeXUnicode

/// A single failed expectation.
public struct CheckFailure {
    public let message: String
    public let file: StaticString
    public let line: UInt
}

/// Records expectations. Deliberately not XCTest: on macOS, XCTest and
/// swift-testing both ship inside Xcode.app, and the conversion engine should
/// be verifiable with only the Command Line Tools installed.
///
/// `Tests/LaTeXUnicodeTests` wraps this for `swift test`, and
/// `latex-squiggly-check` runs it directly. There is only ever one copy of the
/// expectations.
public final class Checker {

    public private(set) var failures: [CheckFailure] = []
    public private(set) var count = 0

    public init() {}

    public func expect(_ condition: Bool,
                       _ message: @autoclosure () -> String,
                       file: StaticString = #filePath, line: UInt = #line) {
        count += 1
        guard !condition else { return }
        failures.append(CheckFailure(message: message(), file: file, line: line))
    }

    public func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected,
               "\(label): expected \(expected), got \(actual)", file: file, line: line)
    }

    public func notNil<T>(_ value: T?, _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
        expect(value != nil, "\(label): expected a value, got nil", file: file, line: line)
    }

    public func isNil<T>(_ value: T?, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        expect(value == nil, "\(label): expected nil, got \(String(describing: value))",
               file: file, line: line)
    }

    public func fail(_ message: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        expect(false, message, file: file, line: line)
    }
}

// MARK: - Conversion expectations

public extension Checker {

    func converted(_ input: String, _ expected: String,
                   file: StaticString = #filePath, line: UInt = #line) {
        switch convert(input) {
        case .converted(let text):
            equal(text, expected, "convert(\(display(input)))", file: file, line: line)
        case let other:
            fail("convert(\(display(input))): expected .converted(\(display(expected))), got \(describe(other))",
                 file: file, line: line)
        }
    }

    func fallback(_ input: String, _ expected: String,
                  file: StaticString = #filePath, line: UInt = #line) {
        switch convert(input) {
        case .fallback(let text, let reason):
            equal(text, expected, "convert(\(display(input)))", file: file, line: line)
            expect(!reason.isEmpty, "convert(\(display(input))): a fallback must explain itself",
                   file: file, line: line)
        case let other:
            fail("convert(\(display(input))): expected .fallback(\(display(expected))), got \(describe(other))",
                 file: file, line: line)
        }
    }

    /// `fragment` is matched case-insensitively, so a check pins the substance
    /// of the message without freezing its wording.
    func unsupported(_ input: String, containing fragment: String? = nil,
                     file: StaticString = #filePath, line: UInt = #line) {
        switch convert(input) {
        case .unsupported(let reason):
            expect(!reason.isEmpty, "convert(\(display(input))): .unsupported must explain itself",
                   file: file, line: line)
            if let fragment {
                expect(reason.lowercased().contains(fragment.lowercased()),
                       "convert(\(display(input))): reason was \(display(reason)), expected it to mention \(display(fragment))",
                       file: file, line: line)
            }
        case let other:
            fail("convert(\(display(input))): expected .unsupported, got \(describe(other))",
                 file: file, line: line)
        }
    }

    func tokenizes(_ input: String, _ expected: [Token],
                   file: StaticString = #filePath, line: UInt = #line) {
        do {
            let actual = try Tokenizer.tokenize(input)
            expect(actual == expected,
                   "tokenize(\(display(input))): expected \(expected), got \(actual)",
                   file: file, line: line)
        } catch {
            fail("tokenize(\(display(input))): threw \(error)", file: file, line: line)
        }
    }

    func tokenizerThrows(_ input: String, _ expected: TokenizerError,
                         file: StaticString = #filePath, line: UInt = #line) {
        do {
            let actual = try Tokenizer.tokenize(input)
            fail("tokenize(\(display(input))): expected \(expected), got \(actual)",
                 file: file, line: line)
        } catch let error as TokenizerError {
            equal(error, expected, "tokenize(\(display(input)))", file: file, line: line)
        } catch {
            fail("tokenize(\(display(input))): threw \(error)", file: file, line: line)
        }
    }
}

/// Escapes control characters so a failure about a tab is legible.
private func display(_ text: String) -> String {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\t", with: "\\t")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private func describe(_ result: ConversionResult) -> String {
    switch result {
    case .converted(let s):         return ".converted(\(display(s)))"
    case .fallback(let s, let r):   return ".fallback(\(display(s)), \(display(r)))"
    case .unsupported(let r):       return ".unsupported(\(display(r)))"
    }
}
