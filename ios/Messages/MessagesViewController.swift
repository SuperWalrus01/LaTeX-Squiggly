import Messages
import SwiftUI
import UIKit

/// LaTeX Squiggly in Messages' app drawer: write LaTeX, see it rendered, and
/// put the image straight into the conversation, with no copy and paste.
final class MessagesViewController: MSMessagesAppViewController {

    private let state = MessagesState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = MessagesRoot(state: state,
                                expand: { [weak self] in self?.requestPresentationStyle(.expanded) },
                                insert: { [weak self] image, source in self?.insert(image, source: source) })
        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        state.expanded = presentationStyle == .expanded
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        state.expanded = presentationStyle == .expanded
    }

    /// Into the message field as a photo, for the user to send, as Photos
    /// does. A unique name each time, since Messages reads the file later.
    private func insert(_ image: UIImage, source: String) {
        guard let file = MathRenderer.jpegFile(image, name: "equation-\(UUID().uuidString)") else { return }
        activeConversation?.insertAttachment(file, withAlternateFilename: "equation.jpg") { _ in }
        state.remember(source)
        requestPresentationStyle(.compact)
    }
}

@MainActor
final class MessagesState: ObservableObject {
    @Published var expanded = false
    @Published var source = ""
    /// Equations sent before, newest first, to send again with one tap.
    @Published private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recent") ?? []

    func remember(_ source: String) {
        recent.removeAll { $0 == source }
        recent.insert(source, at: 0)
        recent = Array(recent.prefix(12))
        UserDefaults.standard.set(recent, forKey: "recent")
        self.source = ""
    }
}

private struct MessagesRoot: View {
    @ObservedObject var state: MessagesState
    let expand: () -> Void
    let insert: (UIImage, String) -> Void
    @State private var options = RenderOptions.saved
    @FocusState private var editing: Bool

    var body: some View {
        if state.expanded { editor } else { drawer }
    }

    /// The app drawer's strip: a button to write, and recent equations.
    private var drawer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button(action: expand) {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.title2)
                        Text("New").font(.footnote.weight(.semibold))
                    }
                    .frame(width: 84, height: 84)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if state.recent.isEmpty {
                    Text("Write LaTeX, see it rendered,\nand send it as an image.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(state.recent, id: \.self) { source in
                    if let image = options.render(source).image {
                        Button { insert(image, source) } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 180, maxHeight: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var editor: some View {
        let result = options.render(state.source)
        return ScrollView {
            VStack(spacing: 16) {
                TextField("LaTeX, like \\frac{a}{b} or $x^2$", text: $state.source, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lineLimit(2...8)
                    .focused($editing)
                    .padding(10)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                RenderedImage(result: result)
                RenderOptionsPicker(options: $options)
                Button {
                    if let image = result.image { insert(image, state.source) }
                } label: {
                    Label("Add to message", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(result.image == nil)
            }
            .padding()
        }
        .onAppear { editing = true }
    }
}
