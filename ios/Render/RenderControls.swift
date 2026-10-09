import SwiftUI
import UniformTypeIdentifiers

/// Size and card colour for rendered images, shared by the app's Render tab,
/// the share sheet and Messages. Each keeps its own copy, since they cannot
/// read each other's settings without an App Group.
struct RenderOptions: Equatable {
    enum Size: String, CaseIterable {
        case small, medium, large
        var fontSize: CGFloat { [.small: 20, .medium: 28, .large: 40][self]! }
        var label: String { [.small: "S", .medium: "M", .large: "L"][self]! }
    }

    var size: Size
    var dark: Bool

    static var saved: RenderOptions {
        let defaults = UserDefaults.standard
        return RenderOptions(size: Size(rawValue: defaults.string(forKey: "renderSize") ?? "") ?? .medium,
                             dark: defaults.bool(forKey: "renderDark"))
    }

    func save() {
        UserDefaults.standard.set(size.rawValue, forKey: "renderSize")
        UserDefaults.standard.set(dark, forKey: "renderDark")
    }

    func render(_ source: String) -> Result<UIImage, MathRenderer.Failure> {
        MathRenderer.passage(source, fontSize: size.fontSize, dark: dark)
    }
}

/// The rendered image, or why there is none.
struct RenderedImage: View {
    let result: Result<UIImage, MathRenderer.Failure>

    var body: some View {
        switch result {
        case .success(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
                .frame(maxWidth: .infinity)
        case .failure(.empty):
            Text("Type some LaTeX, like x^2 or $\\alpha$.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        case .failure(.parse(let message)):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }
}

/// Size and light or dark card, saved as they change.
struct RenderOptionsPicker: View {
    @Binding var options: RenderOptions

    var body: some View {
        HStack(spacing: 12) {
            Picker("Size", selection: $options.size) {
                ForEach(RenderOptions.Size.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Card", selection: $options.dark) {
                Image(systemName: "sun.max").tag(false)
                Image(systemName: "moon").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .onChange(of: options) { $0.save() }
    }
}

/// Copy and Share for a rendered image.
struct RenderActions: View {
    let image: UIImage?
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard let image else { return }
                MathRenderer.copy(image)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if let image {
                ShareLink(item: EquationJPEG(image: image),
                          preview: SharePreview("Equation", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(image == nil)
        .onChange(of: image) { _ in copied = false }
    }
}

/// A rendered image shared as a JPEG file, so apps receive a photo, not a
/// sticker. The file is written only when the user shares, not each time
/// the view draws, which was every key typed.
struct EquationJPEG: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { item in
            guard let file = MathRenderer.jpegFile(item.image) else { throw CocoaError(.fileWriteUnknown) }
            return SentTransferredFile(file)
        }
    }
}

extension Result where Success == UIImage {
    var image: UIImage? {
        if case .success(let image) = self { return image }
        return nil
    }
}
