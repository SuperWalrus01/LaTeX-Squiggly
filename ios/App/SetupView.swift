import SwiftUI

struct SetupView: View {
    @Environment(\.openURL) private var openURL

    private let steps = [
        "Open Settings, then General, Keyboard, Keyboards.",
        "Tap Add New Keyboard and choose LaTeX Squiggly.",
        "Optional: tap LaTeX Squiggly and turn on Allow Full Access to copy rendered images.",
        "In any app, hold the globe key and pick LaTeX Squiggly.",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Wordmark().frame(height: 74, alignment: .leading)
                            Text("Write maths anywhere. Type \\alpha, get α.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image("MascotHello")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 104)
                            .accessibilityHidden(true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }

                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Label {
                            Text(step)
                        } icon: {
                            Image(systemName: "\(index + 1).circle.fill").foregroundStyle(Color.squiggle)
                        }
                    }
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.squiggle)
                } header: {
                    heading("Turn on the keyboard")
                } footer: {
                    // The button opens the app's own page, not General.
                    Text("Open Settings goes straight to LaTeX Squiggly's page. Tap Keyboards there to turn it on.")
                        .foregroundStyle(Color.inkSoft)
                }
                .listRowBackground(Color.card)

                Section(header: heading("How it works")) {
                    Text("Type \\alpha and press space: it becomes α.")
                    Text("For an image, write your maths between $ signs. The bar above the keys shows it rendered. Tap Copy, then paste.")
                    Text("Tap LaTeX in the bar to keep everything as LaTeX. Nothing converts until you tap it again.")
                    Text("Or select any text with maths in it and tap Copy.")
                    Text("The ∑ key has Greek letters and symbols. Hold a key for more.")
                }
                .listRowBackground(Color.card)

                Section(header: heading("Render from anywhere")) {
                    Text("Select LaTeX in any app, tap Share, then LaTeX Squiggly. It renders straight away, ready to copy or send.")
                    Text("In Messages, open the app drawer and pick LaTeX Squiggly to write an equation and add it to your message.")
                }
                .listRowBackground(Color.card)

                Section(header: heading("Privacy")) {
                    Text("Nothing you type leaves your phone. Full Access is used only to put rendered images on the clipboard.")
                    Link("Privacy policy", destination: Links.privacy)
                        .foregroundStyle(Color.squiggle)
                }
                .listRowBackground(Color.card)

                Section(header: heading("About")) {
                    Link("Help and feedback", destination: Links.support)
                        .foregroundStyle(Color.squiggle)
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Version", value: Links.version)
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .squigglyList()
            .navigationTitle("Set up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A section heading in the brand's rounded type.
func heading(_ text: String) -> some View {
    Text(text)
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(Color.inkSoft)
}

struct TryView: View {
    @State private var text = ""

    /// Something the keyboard converted: a Greek letter, a script, a symbol.
    private var converted: Bool {
        text.unicodeScalars.contains { scalar in
            !scalar.isASCII && (scalar.properties.isMath || (0x370...0x3FF).contains(scalar.value)
                                || (0x2070...0x209F).contains(scalar.value) || [0xB2, 0xB3, 0xB9].contains(scalar.value))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(converted ? "MascotCelebrate" : "MascotLaptop")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 76)
                        .accessibilityHidden(true)
                    Text(converted
                         ? "That's it. Hold a key for more symbols, or tap the bar to see your equation large."
                         : "Switch to LaTeX Squiggly with the globe key, then try \\alpha, $x^2$ or \\frac{1}{2} followed by space.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkSoft)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: converted)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule))
            }
            .padding()
            .background(Color.paper)
            .tint(.squiggle)
            .navigationTitle("Try it")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
