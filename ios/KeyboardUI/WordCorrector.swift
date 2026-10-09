import UIKit

/// Suggestions for plain words, with the system's dictionary, for the bar
/// above the keys. Nothing is ever corrected on its own: a word changes only
/// when the user taps a suggestion. LaTeX is never touched; the model only
/// asks about words outside maths.
@MainActor
final class WordCorrector {

    struct Offer: Equatable {
        /// The word as typed.
        let typed: String
        /// Up to two words to offer in its place, best first.
        let suggestions: [String]
    }

    private let checker = UITextChecker()
    private let language: String
    /// The user's text replacements from Settings, by shortcut.
    private var replacements: [String: String] = [:]
    /// Names from Contacts, and the like, never respelled.
    private var known: Set<String> = []
    /// The last offer made. The bar asks again for the same word after each
    /// key and each time the host reports its text, and the dictionary's
    /// guesses take long enough to make typing lag.
    private var lastOffer: Offer?

    init() {
        let languages = UITextChecker.availableLanguages
        language = languages.first { $0.hasPrefix("en_US") }
            ?? languages.first { $0.hasPrefix("en") } ?? "en_US"
    }

    func use(_ lexicon: UILexicon) {
        lastOffer = nil
        for entry in lexicon.entries {
            if entry.userInput == entry.documentText {
                known.insert(entry.userInput.lowercased())
            } else {
                replacements[entry.userInput.lowercased()] = entry.documentText
            }
        }
    }

    /// The word being typed at the end of `before`. Nil for the end of a
    /// LaTeX command, `\alpha`, or of something like `x_ab` or `2nd`.
    static func currentWord(in before: String) -> String? {
        let word = before.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        guard !word.isEmpty, word.contains(where: \.isLetter) else { return nil }
        if let previous = before.dropLast(word.count).last,
           previous == "\\" || previous == "_" || previous == "^" || previous.isNumber {
            return nil
        }
        return String(word.reversed())
    }

    /// The user's text replacement or a close spelling first, then the words
    /// it may be on its way to, then other spellings. Completions come before
    /// other spellings: a word part-typed, like `hel`, is not in the
    /// dictionary yet, and the word it is heading for is likelier.
    func offer(for word: String) -> Offer {
        if let lastOffer, lastOffer.typed == word { return lastOffer }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let spelling = spelling(for: word)
        var candidates = spelling.map { [$0] } ?? []
        candidates += (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
            .map { Self.matchCase($0, to: word) }
        if spelling != nil {
            candidates += (checker.guesses(forWordRange: range, in: word, language: language) ?? [])
                .map { Self.matchCase($0, to: word) }
        }
        var seen: Set<String> = [word]
        let offer = Offer(typed: word, suggestions: Array(candidates.filter { seen.insert($0).inserted }.prefix(2)))
        lastOffer = offer
        return offer
    }

    /// The likeliest intended spelling, when the word is misspelled and the
    /// dictionary's best guess is close: one slip in a short word, two in a
    /// longer one. Offered, never applied.
    private func spelling(for word: String) -> String? {
        let lower = word.lowercased()
        if let replacement = replacements[lower] { return replacement }
        if word == "i" { return "I" }
        guard word.count >= 2, !known.contains(lower),
              // Capitals inside a word, as in iPhone or LaTeX, are meant.
              !word.dropFirst().contains(where: \.isUppercase) else { return nil }

        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                       wrap: false, language: language)
        guard misspelled.location != NSNotFound,
              let guess = checker.guesses(forWordRange: range, in: word, language: language)?.first,
              Self.distance(lower, guess.lowercased()) <= (word.count <= 4 ? 1 : 2) else { return nil }
        return Self.matchCase(guess, to: word)
    }

    /// `Teh` becomes `The`, and `TEH` becomes `THE`.
    static func matchCase(_ guess: String, to word: String) -> String {
        if word.count > 1, word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return guess.uppercased() }
        if word.first?.isUppercase == true { return guess.prefix(1).uppercased() + guess.dropFirst() }
        return guess
    }

    /// Edits between two words, where swapping two neighbours counts as one,
    /// so `teh` is one slip from `the`.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
