import Foundation
import WebKit

/// Serves the renderer window's page and scripts to its web view, at
/// `squiggly://app/`.
///
/// A web view will not load ES modules or `fetch` anything from `file://`
/// pages, and the renderer needs both, so its files come through a URL scheme
/// of the app's own instead. They are the extension's own files, laid out by
/// `Web/files.json`: `scripts/build-mac-app.sh` copies them into the bundle's
/// `Resources/web/`, and when the app runs unbundled, from `swift run`, they
/// are read straight from the repository by the same map.
@MainActor
final class RendererFiles: NSObject, WKURLSchemeHandler {

    static let scheme = "squiggly"
    static let pageURL = URL(string: "\(scheme)://app/index.html")!

    private static let types = [
        "html": "text/html",
        "js": "text/javascript",
        "css": "text/css",
        "json": "application/json",
        "svg": "image/svg+xml",
        "png": "image/png",
    ]

    private let resolve: (String) -> URL?

    override init() {
        if let web = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: web.path) {
            resolve = { web.appendingPathComponent($0) }
        } else {
            resolve = RendererFiles.fromRepository()
        }
        super.init()
    }

    /// Sources/LaTeXSquigglyApp/RendererFiles.swift is three folders below
    /// the repository, which holds the map and every file it names.
    private static func fromRepository() -> (String) -> URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let mapURL = root.appendingPathComponent("Sources/LaTeXSquigglyApp/Web/files.json")
        guard let data = try? Data(contentsOf: mapURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [String: String] else {
            return { _ in nil }
        }
        return { served in
            if let file = files[served] { return root.appendingPathComponent(file) }
            for (prefix, folder) in files where prefix.hasSuffix("/") && served.hasPrefix(prefix) {
                return root.appendingPathComponent(folder)
                    .appendingPathComponent(String(served.dropFirst(prefix.count)))
            }
            return nil
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let served = String(url.path.drop(while: { $0 == "/" }))
        // Only the files the map names: nothing above them, whatever the path.
        guard !served.split(separator: "/").contains(".."),
              let file = resolve(served.isEmpty ? "index.html" : served),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = Self.types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type,
                                                      "Content-Length": String(data.count)])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Every file is answered in one go in start, so there is nothing to stop.
    }
}
