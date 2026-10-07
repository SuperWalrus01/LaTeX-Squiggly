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
                Section("Turn on the keyboard") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Label(step, systemImage: "\(index + 1).circle")
                    }
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Section("How it works") {
                    Text("Type LaTeX like \\alpha or $x^2$ and press space: it becomes α or x².")
                    Text("The ∑ key opens Greek letters, operators and templates like \\frac{}{}.")
                    Text("Tap the rendered equation above the keys for a large preview, then Copy to paste it as an image.")
                    Text("Hold a key for more: accents on letters, and related symbols on math keys.")
                }
                Section("Render from anywhere") {
                    Text("Select LaTeX in any app, tap Share, then LaTeX Squiggly. It renders straight away, ready to copy or send.")
                    Text("In Messages, open the app drawer and pick LaTeX Squiggly to write an equation and add it to your message.")
                }
                Section("Privacy") {
                    Text("Nothing you type leaves your phone. Full Access is used only to put rendered images on the clipboard.")
                }
            }
            .navigationTitle("LaTeX Squiggly")
        }
    }
}

struct TryView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Try it")
        }
    }
}
