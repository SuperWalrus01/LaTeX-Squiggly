import SwiftMath
import SwiftUI

/// Sizes measured from the iOS 26 keyboard on a 390-point iPhone.
enum Metrics {
    static let stripHeight: CGFloat = 46
    static let keyHeight: CGFloat = 43
    static let rowGap: CGFloat = 11
    static let keyGap: CGFloat = 6
    static let sideMargin: CGFloat = 6.67
    static let cornerRadius: CGFloat = 7
    static let rows = 4
    static let rowPitch = keyHeight + rowGap
}

struct KeyboardView: View {
    static let height = Metrics.stripHeight + Metrics.rowPitch * CGFloat(Metrics.rows)

    @ObservedObject var model: KeyboardModel
    @State private var frames: [KeyFrame] = []

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 2 * Metrics.sideMargin - 9 * Metrics.keyGap) / 10
            let inset = Metrics.sideMargin - Metrics.keyGap / 2
            VStack(spacing: 0) {
                StripView(model: model)
                    .frame(height: Metrics.stripHeight)
                    .padding(.horizontal, inset)
                if model.previewOpen {
                    PreviewPanel(model: model)
                        .frame(height: Metrics.rowPitch * CGFloat(Metrics.rows))
                        .padding(.horizontal, inset + Metrics.keyGap / 2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(Layouts.rows(for: model.page, globe: model.needsGlobe).enumerated()),
                                id: \.offset) { index, row in
                            RowView(items: row, row: index, unit: unit, model: model, presses: model.presses)
                        }
                    }
                    .padding(.horizontal, inset)
                    // The touch surface covers the margins too, so a touch at
                    // the screen's edge still types the key beside it.
                    .coordinateSpace(name: KeyTouchLayer.space)
                    .onPreferenceChange(KeyFramesKey.self) { frames = $0 }
                    .overlay(AlternatesView(model: model, presses: model.presses))
                    .overlay(KeyTouchLayer(model: model, frames: frames))
                }
            }
        }
        .frame(height: Self.height)
        .onAppear { model.refresh() }
    }
}

// MARK: - Rows and keys

private struct RowView: View {
    let items: KeyRow
    let row: Int
    let unit: CGFloat
    @ObservedObject var model: KeyboardModel
    let presses: KeyPresses

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                switch item {
                case .spacer:
                    Spacer(minLength: 0)
                case .key(let key):
                    KeyView(key: key, id: KeyID(row: row, index: index), unit: unit,
                            edge: edge(of: index), model: model, presses: presses)
                }
            }
        }
        .frame(height: Metrics.rowPitch)
    }

    private func edge(of index: Int) -> HorizontalEdge? {
        if index == 0 { return .leading }
        if index == items.count - 1 { return .trailing }
        return nil
    }
}

private struct KeyView: View {
    let key: Key
    let id: KeyID
    let unit: CGFloat
    let edge: HorizontalEdge?
    @ObservedObject var model: KeyboardModel
    @ObservedObject var presses: KeyPresses

    /// Touches are handled by `KeyTouchLayer`, over all the keys.
    private var pressed: Bool { presses.keys.contains(id) }

    var body: some View {
        face
            .frame(height: Metrics.keyHeight)
            .frame(maxWidth: key.width == nil ? .infinity : nil)
            .frame(width: key.width.map { unit * $0 + Metrics.keyGap * ($0 - 1) })
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: KeyFramesKey.self,
                    value: [KeyFrame(id: id, key: key, frame: geo.frame(in: .named(KeyTouchLayer.space)))])
            })
            .overlay(alignment: .bottom) {
                if pressed && key.showsCallout {
                    Callout(text: label, edge: edge)
                }
            }
            .padding(.horizontal, Metrics.keyGap / 2)
            .padding(.vertical, Metrics.rowGap / 2)
            .zIndex(pressed ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAction { model.perform(key.action) }
    }

    private var face: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(background)
                .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
            content
                .foregroundStyle(isAccented ? Color.white : Color.primary)
                // Labels clear while space works as a trackpad, as in iOS.
                .opacity(model.cursorMode ? 0 : 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch key.action {
        case .shift:
            Image(systemName: model.shift == .locked ? "capslock.fill"
                  : model.shift == .on ? "shift.fill" : "shift")
                .font(.system(size: 20, weight: .medium))
        case .backspace:
            Image(systemName: pressed ? "delete.left.fill" : "delete.left")
                .font(.system(size: 20, weight: .regular))
        case .newline:
            if let text = model.returnLabel {
                Text(text).font(.system(size: 17))
            } else {
                Image(systemName: "return").font(.system(size: 20, weight: .regular))
            }
        case .nextKeyboard:
            Image(systemName: "globe").font(.system(size: 20))
        case .space:
            Color.clear
        case .toggleOutput:
            Text(model.output == .unicode ? "α" : "\\α").font(.system(size: 18))
        case .page:
            Text(key.label).font(.system(size: key.label == "∑" ? 21 : 17))
        default:
            Text(label).font(.system(size: 25, weight: .regular))
        }
    }

    /// Letters show lowercase until shift is on, as the system's do.
    private var label: String {
        if case .insert = key.action, model.shift != .off { return key.label.uppercased() }
        return key.label
    }

    /// Send, search and the like get a blue return key, as in iOS.
    private var isAccented: Bool {
        if case .newline = key.action { return model.returnLabel != nil }
        return false
    }

    private var background: Color {
        if isAccented { return pressed ? .accentPressed : .accentColor }
        // Text keys show the pop-up instead of darkening.
        return pressed && !key.showsCallout ? .keyPressed : .key
    }

    private var accessibilityName: String {
        switch key.action {
        case .shift: return "shift"
        case .backspace: return "delete"
        case .newline: return model.returnLabel ?? "return"
        case .space: return "space"
        case .toggleOutput: return model.output == .unicode ? "Typing symbols" : "Typing LaTeX"
        case .math(let source): return source
        default: return label
        }
    }
}

/// The enlarged letter that appears above a pressed key.
private struct Callout: View {
    let text: String
    let edge: HorizontalEdge?

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(Color.primary)
            .frame(width: 52, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.key)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            )
            // Keys at the ends push their pop-up inward, so it stays on screen.
            .offset(x: edge == .leading ? 8 : edge == .trailing ? -8 : 0,
                    y: -Metrics.keyHeight + 2)
            .allowsHitTesting(false)
    }
}

// MARK: - The bar above the keys

private struct StripView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Group {
            switch model.strip {
            case .quick:
                slots(Self.quickKeys.map { item in
                    AnyView(StripButton { model.perform(item.action) } label: {
                        Text(item.label).font(.system(size: 18))
                    })
                })
            case .suggestions(let suggestions):
                slots(suggestions.map { suggestion in
                    AnyView(StripButton { model.accept(suggestion) } label: {
                        HStack(spacing: 6) {
                            if let glyph = suggestion.glyph {
                                Text(glyph).font(.system(size: 19))
                            }
                            Text("\\" + suggestion.command)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    })
                })
            case .words(let offer):
                words(offer)
            case .math(let latex):
                mathPreview(latex: latex)
            case .notice(let message):
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.stripText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 6)
    }

    /// As in iOS: the word as typed in quotes, then what space will correct
    /// it to, in bold, or the likeliest completions.
    private func words(_ offer: WordCorrector.Offer) -> some View {
        var choices: [(label: String, word: String, bold: Bool, keep: Bool)] = [
            ("\u{201C}\(offer.typed)\u{201D}", offer.typed, false, true),
        ]
        if let correction = offer.correction { choices.append((correction, correction, true, false)) }
        choices += offer.others.map { ($0, $0, false, false) }
        return slots(choices.map { choice in
            AnyView(StripButton { model.accept(word: choice.word, keepingTyped: choice.keep) } label: {
                Text(choice.label)
                    .font(.system(size: 17, weight: choice.bold ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            })
        })
    }

    /// Typeset LaTeX. Tap it for a large preview, or Copy for the image.
    private func mathPreview(latex: String) -> some View {
        HStack(spacing: 0) {
            StripButton { model.openPreview() } label: {
                // Empty braces show as boxes, as in an equation editor.
                MathLabel(latex: MathRenderer.stripDelimiters(latex)
                    .replacingOccurrences(of: "{}", with: "{\\square}"))
                    .padding(.horizontal, 10)
            }
            divider
            StripButton { model.copyRendering() } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
                    Text(model.copied ? "Copied" : "Copy")
                }
                .font(.system(size: 15))
            }
            .frame(width: 96)
        }
    }

    private func slots(_ views: [AnyView]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(views.enumerated()), id: \.offset) { index, view in
                if index > 0 { divider }
                view
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.stripDivider)
            .frame(width: 1, height: 24)
    }

    private static let quickKeys: [(label: String, action: KeyAction)] = [
        ("$…$", .template("$$", back: 1)),
        ("{ }", .template("{}", back: 1)),
        ("x²", .template("^{}", back: 1)),
        ("x₂", .template("_{}", back: 1)),
        ("a⁄b", .template("\\frac{}{}", back: 3)),
    ]
}

private struct StripButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Color.stripText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(StripButtonStyle())
    }
}

private struct StripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.keyPressed : .clear)
                    .padding(.vertical, 4)
            )
    }
}

/// SwiftMath's label, sized to the bar.
private struct MathLabel: UIViewRepresentable {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.fontSize = 20
        label.labelMode = .text
        label.textAlignment = .center
        label.displayErrorInline = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        // Setting it typesets again, so only when it changed.
        if label.latex != latex { label.latex = latex }
        label.textColor = colorScheme == .dark ? .white : .black
    }
}

// MARK: - Held keys

/// The options of a held key, over the keys, with the one under the finger
/// highlighted, as in iOS.
private struct AlternatesView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var presses: KeyPresses

    var body: some View {
        if let popup = presses.popup {
            HStack(spacing: 0) {
                ForEach(Array(popup.options.enumerated()), id: \.offset) { index, key in
                    Text(label(key))
                        .font(.system(size: 24))
                        .foregroundStyle(index == popup.selected ? Color.white : Color.primary)
                        .frame(width: popup.cellWidth - 2, height: popup.frame.height - 10)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(index == popup.selected ? Color.accentColor : .clear)
                        )
                        .frame(width: popup.cellWidth)
                }
            }
            .frame(width: popup.frame.width, height: popup.frame.height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.key)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            )
            .position(x: popup.frame.midX, y: popup.frame.midY)
            .allowsHitTesting(false)
        }
    }

    private func label(_ key: Key) -> String {
        if case .insert = key.action, model.shift != .off { return key.label.uppercased() }
        return key.label
    }
}

// MARK: - Large preview

/// The rendering at the size it will be copied, in place of the keys, with
/// its size and light or dark card. Tapping the bar's equation opens it.
private struct PreviewPanel: View {
    @ObservedObject var model: KeyboardModel

    private var latex: String? {
        if case .math(let latex) = model.strip { return latex }
        return nil
    }

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let latex,
                   case .success(let image) = MathRenderer.image(latex: latex,
                                                                fontSize: model.renderStyle.size.fontSize,
                                                                dark: model.renderStyle.dark) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .keyShadow, radius: 0, y: 1)
                } else {
                    Text("Nothing to render here.").foregroundStyle(Color.stripText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Picker("Size", selection: style(\.size)) {
                    Text("S").tag(KeyboardModel.RenderStyle.Size.small)
                    Text("M").tag(KeyboardModel.RenderStyle.Size.medium)
                    Text("L").tag(KeyboardModel.RenderStyle.Size.large)
                }
                .pickerStyle(.segmented)
                Picker("Card", selection: style(\.dark)) {
                    Image(systemName: "sun.max").tag(false)
                    Image(systemName: "moon").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 8) {
                panelButton(model.copied ? "Copied" : "Copy",
                            systemImage: model.copied ? "checkmark" : "doc.on.doc", accented: true) {
                    model.copyRendering()
                }
                panelButton("Keys", systemImage: "keyboard", accented: false) {
                    model.closePreview()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func style<Value>(_ path: WritableKeyPath<KeyboardModel.RenderStyle, Value>) -> Binding<Value> {
        Binding(get: { model.renderStyle[keyPath: path] },
                set: { value in
                    var style = model.renderStyle
                    style[keyPath: path] = value
                    model.setRenderStyle(style)
                })
    }

    private func panelButton(_ title: String, systemImage: String, accented: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accented ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .fill(accented ? Color.accentColor : Color.key)
                        .shadow(color: .keyShadow, radius: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Colours

extension Color {
    /// Measured from the iOS 26 keyboard: white keys in light mode, grey in dark.
    static let key = dynamic(light: UIColor.white, dark: UIColor(white: 61 / 255, alpha: 1))
    static let keyPressed = dynamic(light: UIColor(red: 0.74, green: 0.76, blue: 0.79, alpha: 1),
                                    dark: UIColor(white: 0.40, alpha: 1))
    static let keyShadow = dynamic(light: UIColor(white: 0, alpha: 0.12), dark: UIColor(white: 0, alpha: 0.3))
    static let accentPressed = Color.accentColor.opacity(0.7)
    static let stripText = dynamic(light: UIColor(red: 54 / 255, green: 56 / 255, blue: 60 / 255, alpha: 1),
                                   dark: UIColor(white: 172 / 255, alpha: 1))
    static let stripDivider = dynamic(light: UIColor(red: 208 / 255, green: 210 / 255, blue: 215 / 255, alpha: 1),
                                      dark: UIColor(red: 50 / 255, green: 50 / 255, blue: 52 / 255, alpha: 1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
