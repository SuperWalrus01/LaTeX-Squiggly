import SwiftMath
import SwiftUI

/// Sizes measured from the iOS 26 keyboard on a 390-point iPhone, and the
/// shorter keys it has in landscape, where the screen has little height.
struct Metrics: Equatable {
    static let keyGap: CGFloat = 6
    static let sideMargin: CGFloat = 6.67
    static let cornerRadius: CGFloat = 7
    static let rows = 4

    let stripHeight: CGFloat
    let keyHeight: CGFloat
    let rowGap: CGFloat
    /// Pop-ups over pressed keys. Landscape has no room above the top row
    /// for them, so pressed keys darken instead, as on iPad.
    let callouts: Bool

    var rowPitch: CGFloat { keyHeight + rowGap }
    var height: CGFloat { stripHeight + rowPitch * CGFloat(Self.rows) }

    static let portrait = Metrics(stripHeight: 46, keyHeight: 43, rowGap: 11, callouts: true)
    static let landscape = Metrics(stripHeight: 38, keyHeight: 32, rowGap: 7, callouts: false)

    /// Landscape on an iPhone is a compact height.
    static func `for`(verticalSizeClass: UserInterfaceSizeClass?) -> Metrics {
        verticalSizeClass == .compact ? .landscape : .portrait
    }
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = Metrics.portrait
}

extension EnvironmentValues {
    var keyboardMetrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @State private var frames: [KeyFrame] = []
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let metrics = Metrics.for(verticalSizeClass: verticalSizeClass)
        GeometryReader { geo in
            let unit = (geo.size.width - 2 * Metrics.sideMargin - 9 * Metrics.keyGap) / 10
            let inset = Metrics.sideMargin - Metrics.keyGap / 2
            VStack(spacing: 0) {
                StripView(model: model)
                    .frame(height: metrics.stripHeight)
                    .padding(.horizontal, inset)
                if model.previewOpen {
                    PreviewPanel(model: model)
                        .frame(height: metrics.rowPitch * CGFloat(Metrics.rows))
                        .padding(.horizontal, inset + Metrics.keyGap / 2)
                } else if model.page == .emoji {
                    EmojiPanel(model: model)
                        .frame(height: metrics.rowPitch * CGFloat(Metrics.rows))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(Layouts.rows(for: model.page, globe: model.needsGlobe, field: model.field).enumerated()),
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
                    .overlay(KeyTouchLayer(model: model, frames: frames, metrics: metrics))
                }
            }
        }
        .frame(height: metrics.height)
        .environment(\.keyboardMetrics, metrics)
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
    @Environment(\.keyboardMetrics) private var metrics

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
        .frame(height: metrics.rowPitch)
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
    @Environment(\.keyboardMetrics) private var metrics

    /// Touches are handled by `KeyTouchLayer`, over all the keys.
    private var pressed: Bool { presses.keys.contains(id) }

    private var callout: Bool { key.showsCallout && metrics.callouts }

    var body: some View {
        face
            .frame(height: metrics.keyHeight)
            .frame(maxWidth: key.width == nil ? .infinity : nil)
            .frame(width: key.width.map { unit * $0 + Metrics.keyGap * ($0 - 1) })
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: KeyFramesKey.self,
                    value: [KeyFrame(id: id, key: key, frame: geo.frame(in: .named(KeyTouchLayer.space)))])
            })
            .overlay {
                if pressed && callout {
                    GeometryReader { geo in
                        Callout(text: label, key: geo.size, edge: edge)
                    }
                }
            }
            .padding(.horizontal, Metrics.keyGap / 2)
            .padding(.vertical, metrics.rowGap / 2)
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
        case .page(.emoji):
            Image(systemName: "face.smiling").font(.system(size: 20))
        case .space:
            // Empty, as in iOS, except to say LaTeX is on.
            if model.output == .latex {
                Text("LaTeX").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.secondary)
            } else {
                Color.clear
            }
        case .page:
            Text(key.label).font(.system(size: 17))
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
        return pressed && !callout ? .keyPressed : .key
    }

    private var accessibilityName: String {
        switch key.action {
        case .shift: return "shift"
        case .backspace: return "delete"
        case .newline: return model.returnLabel ?? "return"
        case .space: return "space"
        case .nextKeyboard: return "next keyboard"
        case .page(.emoji): return "emoji"
        case .math(let source): return source
        default: return label
        }
    }
}

/// The balloon a pressed key grows into, as in iOS: the key itself, a short
/// curved neck, and a wider head above with the letter in it, all one shape.
/// Sizes measured from the iOS 26 keyboard. Keys at the ends of a row keep
/// the head flush with their outer side, so it stays on screen.
private struct Callout: View {
    let text: String
    /// The key's face, which the balloon's foot covers exactly.
    let key: CGSize
    let edge: HorizontalEdge?

    private let headHeight: CGFloat = 46
    private let neck: CGFloat = 12
    private var headWidth: CGFloat { key.width + 22 }
    private var height: CGFloat { headHeight + neck + key.height }

    /// The head's left side, relative to the key's.
    private var headX: CGFloat {
        switch edge {
        case .leading: return 0
        case .trailing: return key.width - headWidth
        default: return (key.width - headWidth) / 2
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            BalloonShape(keyX: -headX, keyWidth: key.width, headHeight: headHeight, neck: neck)
                .fill(Color.key)
                .shadow(color: .keyShadow, radius: 1, y: 0.5)
            Text(text)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Color.primary)
                .frame(width: headWidth, height: headHeight)
        }
        .frame(width: headWidth, height: height)
        .offset(x: headX, y: key.height - height)
        .allowsHitTesting(false)
    }
}

/// The outline of `Callout`, in its own coordinates: the head across the
/// top, the key's face at the bottom, joined by curves.
private struct BalloonShape: Shape {
    let keyX: CGFloat
    let keyWidth: CGFloat
    let headHeight: CGFloat
    let neck: CGFloat

    func path(in rect: CGRect) -> Path {
        let headRadius: CGFloat = 10
        let keyRadius = Metrics.cornerRadius
        let left = keyX, right = keyX + keyWidth
        let headBottom = headHeight, keyTop = headHeight + neck
        let bottom = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: 0, y: headRadius))
        path.addQuadCurve(to: CGPoint(x: headRadius, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: rect.maxX - headRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: headRadius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: headBottom))
        path.addCurve(to: CGPoint(x: right, y: keyTop),
                      control1: CGPoint(x: rect.maxX, y: headBottom + neck * 0.6),
                      control2: CGPoint(x: right, y: keyTop - neck * 0.6))
        path.addLine(to: CGPoint(x: right, y: bottom - keyRadius))
        path.addQuadCurve(to: CGPoint(x: right - keyRadius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + keyRadius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - keyRadius), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: keyTop))
        path.addCurve(to: CGPoint(x: 0, y: headBottom),
                      control1: CGPoint(x: left, y: keyTop - neck * 0.6),
                      control2: CGPoint(x: 0, y: headBottom + neck * 0.6))
        path.closeSubpath()
        return path
    }
}

// MARK: - The bar above the keys

private struct StripView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    /// The LaTeX switch and the ∑ key stay at the ends of the bar whatever
    /// it shows between them, so they are always where the thumb expects.
    var body: some View {
        HStack(spacing: 0) {
            modeSwitch.frame(width: 72)
            divider
            middle
            divider
            mathPage.frame(width: 50)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var middle: some View {
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
            case .selection(let text):
                selectionPreview(text)
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
        .frame(maxWidth: .infinity)
    }

    /// LaTeX on or off: filled orange while on, when nothing converts, and
    /// outlined while off, so it reads as a switch rather than a title.
    private var modeSwitch: some View {
        let on = model.output == .latex
        return StripButton { model.perform(.toggleOutput) } label: {
            Text("LaTeX")
                .font(.system(size: 15, weight: on ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Color.white : Color.stripText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(on ? Color.squiggleAccent : Color.clear))
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.stripDivider, lineWidth: 1.5))
        }
        .accessibilityLabel("LaTeX")
        .accessibilityValue(on ? "on" : "off")
    }

    /// The page of Greek letters and symbols, and back to the letters from it.
    private var mathPage: some View {
        let on = model.page == .math
        return StripButton { model.perform(.page(on ? .letters : .math)) } label: {
            Text("∑")
                .font(.system(size: 20))
                .foregroundStyle(on ? Color.white : Color.stripText)
                .frame(width: 36, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? Color.squiggleAccent : Color.clear))
        }
        .accessibilityLabel(on ? "letters" : "Greek letters and symbols")
    }

    /// A selection, typeset small with its words. Tap it for the large
    /// preview, or Copy for the image.
    private func selectionPreview(_ text: String) -> some View {
        HStack(spacing: 0) {
            StripButton { model.openPreview() } label: {
                if case .success(let image) = MathRenderer.passage(text, fontSize: 14,
                                                                   dark: colorScheme == .dark) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                } else {
                    Text("Can't render the selection").font(.system(size: 14))
                }
            }
            divider
            copyButton
        }
    }

    /// As in iOS: the word as typed in quotes, to keep it, then other words
    /// to put in its place. None is bold, because none is applied unless
    /// tapped.
    private func words(_ offer: WordCorrector.Offer) -> some View {
        let choices = [("\u{201C}\(offer.typed)\u{201D}", offer.typed)] + offer.suggestions.map { ($0, $0) }
        return slots(choices.map { label, word in
            AnyView(StripButton { model.accept(word: word) } label: {
                Text(label)
                    .font(.system(size: 17))
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
                MathLabel(latex: MathRenderer.restoringLaTeX(MathRenderer.stripDelimiters(latex))
                    .replacingOccurrences(of: "{}", with: "{\\square}"))
                    .padding(.horizontal, 10)
            }
            divider
            copyButton
        }
    }

    private var copyButton: some View {
        StripButton { model.copyRendering() } label: {
            HStack(spacing: 5) {
                Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
                Text(model.copied ? "Copied" : "Copy")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.squiggleAccent)
        }
        .frame(width: 88)
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
    @Environment(\.keyboardMetrics) private var metrics

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if case .success(let image) = model.rendering() {
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
                .frame(height: metrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .fill(accented ? Color.squiggleAccent : Color.key)
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
    /// LaTeX Squiggly's orange, for its own controls above the keys. The keys
    /// themselves keep the system's blue, as in Apple's keyboard.
    static let squiggleAccent = dynamic(light: UIColor(red: 0xE2 / 255, green: 0x66 / 255, blue: 0x0F / 255, alpha: 1),
                                        dark: UIColor(red: 1, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1))
    static let stripText = dynamic(light: UIColor(red: 54 / 255, green: 56 / 255, blue: 60 / 255, alpha: 1),
                                   dark: UIColor(white: 172 / 255, alpha: 1))
    static let stripDivider = dynamic(light: UIColor(red: 208 / 255, green: 210 / 255, blue: 215 / 255, alpha: 1),
                                      dark: UIColor(red: 50 / 255, green: 50 / 255, blue: 52 / 255, alpha: 1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
