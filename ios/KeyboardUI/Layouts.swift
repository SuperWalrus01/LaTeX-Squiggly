/// The pages of keys, as data, so a layout change never touches the views or
/// the model. Proportions follow the iOS 26 keyboard: letter keys are one
/// unit wide, and the other widths are measured from it.

enum KeyboardPage: Hashable {
    case letters, numbers, symbols, math
    /// Drawn by `EmojiPanel` rather than as rows of keys.
    case emoji
}

/// What the text field is for, which changes a few keys, as in iOS: email
/// fields put `@` and `.` beside space, and web fields `/` and `.`.
enum FieldKind: Hashable {
    case text, email, web
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
    /// The settings row in the bar, opened by holding LaTeX.
    case openSettings
    case toggle(KeyboardSetting)
    case page(KeyboardPage)
}

/// What the keyboard keeps for itself, so it needs neither the app nor
/// Full Access to remember it. Haptics still need Full Access to play.
enum KeyboardSetting: String, CaseIterable, Hashable {
    case words, doubleSpaceStop, haptics

    var label: String {
        switch self {
        case .words: return "Words"
        case .doubleSpaceStop: return "Space space ."
        case .haptics: return "Haptics"
        }
    }

    /// Words and the full stop match the system keyboard; haptics are off,
    /// as there.
    var byDefault: Bool { self != .haptics }
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

    static func rows(for page: KeyboardPage, globe: Bool, field: FieldKind = .text) -> [KeyRow] {
        switch page {
        case .letters: return letters(globe: globe, field: field)
        case .numbers: return numbers(globe: globe)
        case .symbols: return symbols(globe: globe)
        case .math:    return math(globe: globe)
        case .emoji:   return []
        }
    }

    // MARK: - Pages

    private static func letters(globe: Bool, field: FieldKind) -> [KeyRow] {
        [
            plain("qwertyuiop"),
            [.spacer] + plain("asdfghjkl") + [.spacer],
            [.key(Key(label: "shift", action: .shift, width: shiftWidth)), .spacer]
                + plain("zxcvbnm")
                + [.spacer, backspace],
            bottom(left: Key(label: "123", action: .page(.numbers), width: bottomKeyWidth),
                   globe: globe,
                   extras: field == .text ? [backslash] : [],
                   trailing: addressKeys(field)),
        ]
    }

    /// Right of space in an address field, as in iOS. Other fields have the
    /// backslash left of space instead, where the system keyboard has its
    /// emoji key: right of space is where thumbs aiming for space land.
    private static func addressKeys(_ field: FieldKind) -> [Key] {
        let characters: [String]
        switch field {
        case .text: characters = []
        case .email: characters = ["@", "."]
        case .web: characters = ["/", "."]
        }
        return characters.map { Key(label: $0, action: .insert($0), width: bottomKeyWidth) }
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
                   extras: [backslash]),
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
                   extras: [backslash]),
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
                   extras: [backslash],
                   trailing: [Key(label: "123", action: .page(.numbers), width: bottomKeyWidth)]),
        ]
    }

    // MARK: - Pieces

    private static let backslash = Key(label: "\\", action: .insert("\\"), width: bottomKeyWidth)

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

    /// 123, an optional globe, the emoji key, extras, space, trailing keys,
    /// return. The ∑ page is opened from the bar above the keys, not from
    /// here. On Face ID iPhones iOS draws the globe itself, below the
    /// keyboard, so `globe` is usually false, and the emoji key stands where
    /// the system keyboard has its own. A keyboard cannot open Apple's emoji,
    /// so the key opens our own page of them. With a globe as well, the small
    /// keys narrow to keep space wide.
    private static func bottom(left: Key, globe: Bool, extras: [Key], trailing: [Key] = []) -> KeyRow {
        let small = globe ? 1.0 : bottomKeyWidth
        var row: [Key] = [left]
        if globe { row.append(Key(label: "globe", action: .nextKeyboard, width: small)) }
        row.append(Key(label: "emoji", action: .page(.emoji), width: small))
        row += extras.map { Key(label: $0.label, action: $0.action, width: globe ? small : $0.width) }
        row.append(Key(label: "space", action: .space, width: nil))
        row += trailing
        row.append(Key(label: "return", action: .newline, width: globe ? 2.0 : returnWidth))
        return row.map(RowItem.key)
    }
}
