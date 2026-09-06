/// One row of the coverage table, with enough context to be searchable.
///
/// The Unicode name is carried deliberately: someone who cannot remember
/// `\succeq` can still find it by typing "succeeds", and someone who does not
/// know the command at all can search "double-struck".
public struct SymbolEntry: Equatable, Sendable {
    public let command: String
    public let glyph: String
    public let unicodeName: String
    public let category: String

    public init(command: String, glyph: String, unicodeName: String, category: String) {
        self.command = command
        self.glyph = glyph
        self.unicodeName = unicodeName
        self.category = category
    }

    /// True when every whitespace-separated term in `query` appears somewhere
    /// in this entry, so "greek capital" narrows rather than widens.
    public func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = "\\\(command) \(unicodeName) \(category) \(glyph)".lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

public enum SymbolTable {

    /// LaTeX command name (without the leading backslash) to its Unicode form.
    ///
    /// Derived from `entries`; the generator rejects duplicate commands, so the
    /// unique-keys precondition here doubles as a check on that invariant.
    public static let symbols: [String: String] =
        Dictionary(uniqueKeysWithValues: entries.map { ($0.command, $0.glyph) })

    /// Every category in table order.
    public static let categories: [String] = {
        var seen = Set<String>()
        return entries.map(\.category).filter { seen.insert($0).inserted }
    }()
}
