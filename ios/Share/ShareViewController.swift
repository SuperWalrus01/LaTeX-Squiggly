import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share sheet's LaTeX Squiggly: select LaTeX in any app, share it, and
/// it is rendered straight away, ready to copy or send on.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let text = await sharedText()
            let sheet = UIHostingController(rootView: ShareSheet(source: text) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            addChild(sheet)
            sheet.view.frame = view.bounds
            sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(sheet.view)
            sheet.didMove(toParent: self)
        }
    }

    /// The selection, which apps hand over as plain text, as attributed text
    /// on the item, or both.
    private func sharedText() async -> String {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let type = UTType.plainText.identifier
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(type) {
                let loaded = try? await provider.loadItem(forTypeIdentifier: type)
                if let text = loaded as? String { return text }
                if let data = loaded as? Data, let text = String(data: data, encoding: .utf8) { return text }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty { return text }
        }
        return ""
    }
}

/// Internal, not private, so the app's debug screens can show it too.
struct ShareSheet: View {
    @State var source: String
    let done: () -> Void
    @State private var options = RenderOptions.saved

    var body: some View {
        let result = options.render(source)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    RenderedImage(result: result)
                    RenderActions(image: result.image)
                    RenderOptionsPicker(options: $options)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LaTeX").font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.inkSoft)
                        TextField("LaTeX", text: $source, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .lineLimit(3...12)
                            .padding(10)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.rule))
                    }
                }
                .padding()
            }
            .background(Color.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark().frame(height: 30) }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
            .tint(.squiggle)
        }
    }
}
