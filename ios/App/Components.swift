import SwiftUI

// The app's building blocks, so every screen is made of the same few things:
// cards on paper, keys drawn as they look on the keyboard, and one orange
// button style.

/// A white card on the paper, softly lifted.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.card)
                    .shadow(color: Color.ink.opacity(0.07), radius: 14, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.rule.opacity(0.7), lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// A key as it looks on the keyboard, for instructions: "tap [space]".
struct KeyCap: View {
    let label: String

    var body: some View {
        Group {
            if let symbol = Self.symbols[label] {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            } else {
                Text(label).font(.system(size: 15, weight: .medium))
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, label.count > 2 ? 9 : 7)
        .frame(minWidth: 28, minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.keyCap)
                .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
        )
        .accessibilityLabel(label)
    }

    /// Keys drawn as icons, as on the keyboard.
    private static let symbols = [
        "globe": "globe", "emoji": "face.smiling", "delete": "delete.left",
        "shift": "shift", "return": "return",
    ]
}

/// Instruction text with keys and code inline, wrapping like a paragraph.
/// `[space]` draws a key and `` `alpha` `` draws code.
struct Instruction: View {
    let text: String
    var font: Font = .system(.body, design: .rounded)

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 7) {
            ForEach(Array(Self.tokens(text).enumerated()), id: \.offset) { _, token in
                view(token)
            }
        }
    }

    @ViewBuilder
    private func view(_ token: Token) -> some View {
        switch token {
        case .word(let word):
            Text(word).font(font).foregroundStyle(Color.ink)
        case .key(let label):
            KeyCap(label: label)
        case .code(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(Color.squiggle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.squiggle.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        case .punctuated(let inner, let mark):
            HStack(spacing: 1) {
                AnyView(view(inner))
                Text(mark).font(font).foregroundStyle(Color.ink)
            }
        }
    }

    indirect enum Token {
        case word(String), key(String), code(String)
        /// A key or code with the punctuation after it, kept together so
        /// no space opens before the comma.
        case punctuated(Token, String)

        var isWord: Bool {
            if case .word = self { return true }
            return false
        }
    }

    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            if rest.first == "[", let close = rest.firstIndex(of: "]") {
                tokens.append(.key(String(rest[rest.index(after: rest.startIndex)..<close])))
                rest = rest[rest.index(after: close)...]
            } else if rest.first == "`", let close = rest.dropFirst().firstIndex(of: "`") {
                tokens.append(.code(String(rest[rest.index(after: rest.startIndex)..<close])))
                rest = rest[rest.index(after: close)...]
            } else {
                let end = rest.firstIndex(where: { $0 == "[" || $0 == "`" }) ?? rest.endIndex
                var words = rest[..<end].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                // Punctuation straight after a key or code joins it.
                if let first = words.first, let mark = first.first, ".,;:!?)".contains(mark),
                   let last = tokens.last, !last.isWord {
                    tokens[tokens.count - 1] = .punctuated(last, first)
                    words.removeFirst()
                }
                tokens += words.filter { !$0.isEmpty }.map { .word($0) }
                rest = rest[end...]
            }
        }
        return tokens
    }
}

/// Lays its children out left to right, wrapping onto new lines, with each
/// line's items centred on one another.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = lines[lines.count - 1].items.isEmpty ? size.width : spacing + size.width
            if lines[lines.count - 1].width + extra > width, !lines[lines.count - 1].items.isEmpty {
                lines.append(Line())
            }
            let gap = lines[lines.count - 1].items.isEmpty ? 0 : spacing
            lines[lines.count - 1].items.append(index)
            lines[lines.count - 1].width += gap + size.width
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
        }
        return lines
    }
}

/// An SF Symbol on a tinted rounded square, for the start of a row.
struct IconTile: View {
    let symbol: String
    var done = false
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: done ? "checkmark" : symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(done ? Color.white : Color.squiggle)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(done ? Color.squiggle : Color.squiggle.opacity(0.12))
            )
    }
}

/// The one big button: orange and full width, or quiet beside it.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.squiggle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(prominent ? Color.squiggle : Color.squiggle.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// How far through something the user is, as a rounded bar.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.rule)
                Capsule().fill(Color.squiggle)
                    .frame(width: max(geo.size.height, geo.size.width * value))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
    }
}

/// A small heading above a group of cards.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

extension Color {
    /// A key's face, light in light mode and grey in dark, as on the keyboard.
    static let keyCap = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.32, alpha: 1) : .white })
}
