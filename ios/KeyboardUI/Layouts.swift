/// The pages of keys, as data, so a layout change never touches the views or
/// the model. Proportions follow the iOS 26 keyboard: letter keys are one
/// unit wide, and the other widths are measured from it.

enum KeyboardPage: Hashable {
    case letters, numbers, symbols, math
}

enum KeyAction: Hashable {
    /// Plain text, shifted when shift is on.
    case insert(String)
    /// A LaTeX command, typed as source or as its Unicode glyph by preference.
    case math(String)
    /// Source with the cursor placed `back` characters from its end, inside
    /// the first empty brace.
    case template(String, back: Int)
    case space, backspace, newline, shift, nextKeyboard, toggleOutput
    case page(KeyboardPage)
}

struct Key: Hashable {
    let label: String
    let action: KeyAction
    /// In letter-key units; `nil` shares out whatever the row has left.
    var width: Double?

    /// Keys that type text get the pop-up when pressed, like the system's.
    var showsCallout: Bool {
        switch action {
        case .insert, .math: return label.count <= 2
        default: return false
        }
    }
}

enum RowItem: Hashable {
    case key(Key)
    /// Flexible space, used to centre a row's middle keys between its ends.
    case spacer
}

typealias KeyRow = [RowItem]

enum Layouts {

    // Widths measured from the system keyboard on a 390-point iPhone, where a
    // letter key is 32.3 points.
    static let shiftWidth = 1.35
    static let bottomKeyWidth = 1.29
    static let returnWidth = 2.3

    static func rows(for page: KeyboardPage, globe: Bool) -> [KeyRow] {
        switch page {
        case .letters: return letters(globe: globe)
        case .numbers: return numbers(globe: globe)
        case .symbols: return symbols(globe: globe)
        case .math:    return math(globe: globe)
        }
    }

    // MARK: - Pages

    private static func letters(globe: Bool) -> [KeyRow] {
        [
            plain("qwertyuiop"),
            [.spacer] + plain("asdfghjkl") + [.spacer],
            [.key(Key(label: "shift", action: .shift, width: shiftWidth)), .spacer]
                + plain("zxcvbnm")
                + [.spacer, backspace],
            bottom(left: Key(label: "123", action: .page(.numbers), width: bottomKeyWidth),
                   globe: globe,
                   extras: [Key(label: "∑", action: .page(.math), width: bottomKeyWidth)],
                   trailing: [Key(label: "\\", action: .insert("\\"), width: bottomKeyWidth)]),
        ]
    }

    private static func numbers(globe: Bool) -> [KeyRow] {
        [
            plain("1234567890"),
            plain("-/:;()$&@\""),
            [.key(Key(label: "#+=", action: .page(.symbols), width: shiftWidth))]
                + wide(".,?!'")
                + [backspace],
            bottom(left: Key(label: "ABC", action: .page(.letters), width: bottomKeyWidth),
                   globe: globe,
                   extras: [Key(label: "∑", action: .page(.math), width: bottomKeyWidth)],
                   trailing: [Key(label: "\\", action: .insert("\\"), width: bottomKeyWidth)]),
        ]
    }

    private static func symbols(globe: Bool) -> [KeyRow] {
        [
            plain("[]{}#%^*+="),
            plain("_\\|~<>€£¥•"),
            [.key(Key(label: "123", action: .page(.numbers), width: shiftWidth))]
                + wide(".,?!'")
                + [backspace],
            bottom(left: Key(label: "ABC", action: .page(.letters), width: bottomKeyWidth),
                   globe: globe,
                   extras: [Key(label: "∑", action: .page(.math), width: bottomKeyWidth)],
                   trailing: [Key(label: "\\", action: .insert("\\"), width: bottomKeyWidth)]),
        ]
    }

    private static func math(globe: Bool) -> [KeyRow] {
        [
            symbols([("α", "alpha"), ("β", "beta"), ("γ", "gamma"), ("δ", "delta"),
                     ("ε", "epsilon"), ("θ", "theta"), ("λ", "lambda"), ("μ", "mu"),
                     ("π", "pi"), ("σ", "sigma")]),
            symbols([("φ", "phi"), ("ω", "omega"), ("Δ", "Delta"), ("Σ", "Sigma"),
                     ("Ω", "Omega"), ("∞", "infty"), ("∂", "partial"), ("∇", "nabla"),
                     ("±", "pm"), ("×", "times")]),
            [.key(Key(label: "·", action: .math("\\cdot"), width: shiftWidth)), .spacer]
                + symbols([("≤", "leq"), ("≥", "geq"), ("≠", "neq"), ("≈", "approx"),
                           ("→", "to"), ("∈", "in"), ("∫", "int")])
                + [.spacer, backspace],
            bottom(left: Key(label: "ABC", action: .page(.letters), width: bottomKeyWidth),
                   globe: globe,
                   extras: [Key(label: "output", action: .toggleOutput, width: bottomKeyWidth)],
                   trailing: [Key(label: "123", action: .page(.numbers), width: bottomKeyWidth)]),
        ]
    }

    // MARK: - Pieces

    private static let backspace = RowItem.key(Key(label: "delete", action: .backspace, width: shiftWidth))

    /// One letter-width key per character.
    private static func plain(_ characters: String) -> KeyRow {
        characters.map { .key(Key(label: String($0), action: .insert(String($0)), width: 1)) }
    }

    /// Keys that share the row's leftover width, like the punctuation row.
    private static func wide(_ characters: String) -> KeyRow {
        characters.map { .key(Key(label: String($0), action: .insert(String($0)), width: nil)) }
    }

    private static func symbols(_ pairs: [(glyph: String, command: String)]) -> KeyRow {
        pairs.map { .key(Key(label: $0.glyph, action: .math("\\" + $0.command), width: 1)) }
    }

    /// 123, an optional globe, extras, space, trailing keys, return. On Face ID
    /// iPhones iOS draws the globe itself, below the keyboard, so `globe` is
    /// usually false.
    private static func bottom(left: Key, globe: Bool, extras: [Key], trailing: [Key]) -> KeyRow {
        var row: [Key] = [left]
        if globe { row.append(Key(label: "globe", action: .nextKeyboard, width: bottomKeyWidth)) }
        row += extras
        row.append(Key(label: "space", action: .space, width: nil))
        row += trailing
        row.append(Key(label: "return", action: .newline, width: returnWidth))
        return row.map(RowItem.key)
    }
}
