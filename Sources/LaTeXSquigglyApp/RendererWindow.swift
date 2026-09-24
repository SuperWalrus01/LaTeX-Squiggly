import AppKit
import UniformTypeIdentifiers
import WebKit

/// The renderer: LaTeX in, an image out, to paste where LaTeX is not
/// understood. The same renderer as the Chrome extension's, the page from
/// `Web/` in a web view, with the app doing what a page cannot: the
/// clipboard, the save panel, and keeping its settings.
///
/// The page talks to the app through one message handler, `squiggly`, and
/// every message is answered; `chrome/renderer/host.js` is the other side.
/// The window is kept once made, so MathJax loads once per launch and the
/// shortcut brings it back at once.
@MainActor
final class RendererWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var webView: WKWebView?
    private let files = RendererFiles()
    private let storage = RendererStorage()

    /// Whatever was in front when the renderer opened, which gets the focus
    /// back when it closes, so ⌘Enter then ⌘V pastes where you were typing.
    private var previousApplication: NSRunningApplication?

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Selects the input, ready to be typed over. Before the page has
        // loaded there is nothing to call, and the page selects it itself.
        webView?.evaluateJavaScript("globalThis.squigglyShown?.()", completionHandler: nil)
    }

    private func hide() {
        window?.orderOut(nil)
        previousApplication?.activate(options: [])
        previousApplication = nil
    }

    // Closing only hides it, so the next show is instant.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: Construction

    private func makeWindow() -> NSWindow {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: RendererFiles.scheme)
        configuration.userContentController.addScriptMessageHandler(
            self, contentWorld: .page, name: "squiggly")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Render LaTeX"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 420)
        window.contentView = webView
        window.center()

        webView.load(URLRequest(url: RendererFiles.pageURL))
        return window
    }
}

// MARK: - Messages from the page

extension RendererWindow: WKScriptMessageHandlerWithReply {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "A message with no op.")
            return
        }
        switch op {
        case "get":
            let area = body["area"] as? String ?? "local"
            let keys = body["keys"] as? [String] ?? []
            replyHandler(storage.get(area: area, keys: keys), nil)

        case "set":
            let area = body["area"] as? String ?? "local"
            storage.set(area: area, items: body["items"] as? [String: Any] ?? [:])
            replyHandler(nil, nil)

        case "shortcut":
            replyHandler(body["name"] as? String == "open-renderer" ? GlobalShortcut.symbols : nil, nil)

        case "close":
            hide()
            replyHandler(nil, nil)

        case "copyImage":
            guard let base64 = body["png"] as? String,
                  let png = Data(base64Encoded: base64),
                  let width = (body["width"] as? NSNumber)?.doubleValue,
                  let height = (body["height"] as? NSNumber)?.doubleValue else {
                replyHandler(nil, "No image to copy.")
                return
            }
            replyHandler(nil, copyImage(png, size: NSSize(width: width, height: height)))

        case "copyText":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
            replyHandler(nil, nil)

        case "save":
            guard let name = body["name"] as? String,
                  let base64 = body["data"] as? String,
                  let data = Data(base64Encoded: base64) else {
                replyHandler(nil, "Nothing to save.")
                return
            }
            save(data, name: name, reply: replyHandler)

        default:
            replyHandler(nil, "Unknown op \(op).")
        }
    }

    /// The PNG with its size in points, which the page measured before scaling
    /// it up. Apps that read the size, which is most Mac apps, then paste a 3×
    /// image at the size it was previewed, and sharp, instead of three times
    /// as large. A TIFF goes with it for apps that take only that.
    private func copyImage(_ png: Data, size: NSSize) -> String? {
        guard let bitmap = NSBitmapImageRep(data: png) else { return "The image could not be read." }
        bitmap.size = size
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let sized = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(sized, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return nil
    }

    private func save(_ data: Data, name: String, reply: @escaping (Any?, String?) -> Void) {
        guard let window else {
            reply(false, nil)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [name.hasSuffix(".svg") ? .svg : .png]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                reply(false, nil)
                return
            }
            do {
                try data.write(to: url)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }
}

// MARK: - Storage

/// The page's two storage areas, as the extension has them: `sync` for the
/// settings and `local` for the last input and the history. On the Mac both
/// are the app's own defaults, one JSON object each, because the page's values
/// can include null, which a property list cannot hold.
@MainActor
struct RendererStorage {

    private func key(_ area: String) -> String {
        area == "sync" ? "rendererSettings" : "rendererLocal"
    }

    private func load(_ area: String) -> [String: Any] {
        guard let text = UserDefaults.standard.string(forKey: key(area)),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    func get(area: String, keys: [String]) -> [String: Any] {
        load(area).filter { keys.contains($0.key) }
    }

    func set(area: String, items: [String: Any]) {
        var stored = load(area)
        stored.merge(items) { _, new in new }
        guard JSONSerialization.isValidJSONObject(stored),
              let data = try? JSONSerialization.data(withJSONObject: stored),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: key(area))
    }
}
