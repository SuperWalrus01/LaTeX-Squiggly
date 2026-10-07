/// What a key offers when held: accents on letters, as in iOS, and related
/// symbols on the math and symbol keys. The key's own character comes first,
/// so letting go without sliding types what the key says.
enum Alternates {

    static func options(for key: Key) -> [Key] {
        let extras: [Key]
        switch key.action {
        case .insert(let text):
            if let accents = accents[text] {
                extras = accents.map { Key(label: String($0), action: .insert(String($0))) }
            } else {
                extras = (symbols[text] ?? []).map(math)
            }
        case .math(let source):
            extras = (commands[String(source.dropFirst())] ?? []).map(math)
        default:
            return []
        }
        return extras.isEmpty ? [] : [key] + extras
    }

    private static func math(_ pair: (glyph: String, command: String)) -> Key {
        Key(label: pair.glyph, action: .math("\\" + pair.command))
    }

    /// The accents the system's English keyboard offers.
    private static let accents: [String: String] = [
        "a": "àáâäæãåā", "c": "çćč", "e": "èéêëēėę", "i": "îïíīįì", "l": "ł",
        "n": "ñń", "o": "ôöòóœøōõ", "s": "ßśš", "u": "ûüùúū", "y": "ÿ", "z": "žźż",
        "-": "–—•", "/": "\\", "$": "€£¥¢", "&": "§", ".": "…", "?": "¿", "!": "¡",
        "'": "‘’", "\"": "“”«»", "%": "‰", "0": "°",
    ]

    /// Plain symbol keys whose held options are math, typed as LaTeX or as
    /// symbols like any math key.
    private static let symbols: [String: [(String, String)]] = [
        "=": [("≠", "neq"), ("≈", "approx"), ("≡", "equiv"), ("≅", "cong")],
        "<": [("≤", "leq"), ("≪", "ll"), ("⊂", "subset")],
        ">": [("≥", "geq"), ("≫", "gg"), ("⊃", "supset")],
        "+": [("±", "pm"), ("∓", "mp")],
        "*": [("×", "times"), ("·", "cdot"), ("÷", "div")],
        "~": [("∼", "sim"), ("≃", "simeq"), ("≈", "approx")],
    ]

    /// Math keys, by command: variants, capitals and near relatives.
    private static let commands: [String: [(String, String)]] = [
        "gamma": [("Γ", "Gamma")],
        "delta": [("Δ", "Delta")],
        "epsilon": [("ϵ", "varepsilon")],
        "theta": [("ϑ", "vartheta"), ("Θ", "Theta")],
        "lambda": [("Λ", "Lambda")],
        "pi": [("ϖ", "varpi"), ("Π", "Pi")],
        "sigma": [("ς", "varsigma"), ("Σ", "Sigma")],
        "phi": [("φ", "varphi"), ("Φ", "Phi")],
        "omega": [("Ω", "Omega")],
        "partial": [("∇", "nabla")],
        "infty": [("ℵ", "aleph")],
        "pm": [("∓", "mp")],
        "times": [("÷", "div"), ("⊗", "otimes"), ("∘", "circ")],
        "cdot": [("∘", "circ"), ("•", "bullet")],
        "leq": [("≪", "ll"), ("⊆", "subseteq"), ("≺", "prec")],
        "geq": [("≫", "gg"), ("⊇", "supseteq"), ("≻", "succ")],
        "neq": [("≡", "equiv"), ("≢", "not\\equiv")],
        "approx": [("∼", "sim"), ("≃", "simeq"), ("≅", "cong"), ("∝", "propto")],
        "to": [("←", "leftarrow"), ("↔", "leftrightarrow"), ("⇒", "Rightarrow"),
               ("⇔", "Leftrightarrow"), ("↦", "mapsto")],
        "in": [("∉", "notin"), ("∋", "ni"), ("⊂", "subset"), ("⊆", "subseteq")],
        "int": [("∬", "iint"), ("∮", "oint"), ("∑", "sum"), ("∏", "prod")],
    ]
}
