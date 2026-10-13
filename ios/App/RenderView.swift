import SwiftUI

/// Renders LaTeX too long for the bar above the keys. Text with `$...$` in it
/// keeps its words, as it does from the share sheet.
struct RenderView: View {
    static let example = "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"

    @State private var latex: String
    @State private var options = RenderOptions.saved
    @FocusState private var editing: Bool

    init(latex: String = RenderView.example) {
        _latex = State(initialValue: latex)
    }

    var body: some View {
        let result = options.render(latex)
        ScrollView {
            VStack(spacing: 22) {
                ScreenTitle(title: "Render", mascot: "MascotIdea")

                VStack(spacing: 10) {
                    SectionTitle("Preview")
                    VStack(spacing: 16) {
                        RenderedImage(result: result)
                            .frame(minHeight: 110)
                        RenderOptionsPicker(options: $options)
                        RenderActions(image: result.image)
                    }
                    .card()
                }

                VStack(spacing: 10) {
                    SectionTitle("LaTeX")
                    TextField("x^2, \\frac{a}{b}, or words with $x$ in them", text: $latex, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...10)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($editing)
                        .foregroundStyle(Color.ink)
                        .card()
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(editing ? Color.squiggle.opacity(0.5) : .clear, lineWidth: 2)
                        )
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.squiggle)
                        .padding(.top, 2)
                    Text("Select LaTeX in any app, tap Share, then LaTeX Squiggly to render it there.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.squiggle.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper.ignoresSafeArea())
        .tint(.squiggle)
    }
}
