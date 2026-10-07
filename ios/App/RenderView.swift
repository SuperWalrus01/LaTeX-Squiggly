import SwiftUI

/// Renders LaTeX too long for the bar above the keys. Text with `$...$` in it
/// keeps its words, as it does from the share sheet.
struct RenderView: View {
    static let example = "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"

    @State private var latex: String
    @State private var options = RenderOptions.saved

    init(latex: String = RenderView.example) {
        _latex = State(initialValue: latex)
    }

    var body: some View {
        let result = options.render(latex)
        NavigationStack {
            Form {
                Section("LaTeX") {
                    TextField("LaTeX", text: $latex, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Preview") {
                    RenderedImage(result: result)
                    RenderOptionsPicker(options: $options)
                    RenderActions(image: result.image)
                }
                Section {
                    Text("Select LaTeX in any app, tap Share, then LaTeX Squiggly to render it there.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Render")
        }
    }
}
