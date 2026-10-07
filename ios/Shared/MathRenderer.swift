import SwiftMath
import UIKit
import UniformTypeIdentifiers

/// Typesets LaTeX to an image with SwiftMath.
///
/// Native rather than MathJax in a web view: a keyboard extension is killed
/// past a few tens of megabytes, and a WKWebView alone can cost that much.
enum MathRenderer {

    enum Failure: Error, Equatable {
        case empty
        case parse(String)
    }

    /// One equation on a card, for pasting or sharing. The card is opaque on
    /// purpose: chat apps like WhatsApp turn a transparent image into a
    /// sticker, and a transparent one vanishes in a dark-mode chat anyway.
    static func image(latex: String,
                      fontSize: CGFloat = 28,
                      display: Bool = true,
                      dark: Bool = false) -> Result<UIImage, Failure> {
        let source = stripDelimiters(latex)
        guard !source.isEmpty else { return .failure(.empty) }
        switch math(source, fontSize: fontSize, display: display, dark: dark) {
        case .success(let piece):
            return .success(card(size: CGSize(width: piece.width, height: piece.ascent + piece.descent),
                                 fontSize: fontSize, dark: dark) { origin in
                piece.image.draw(at: origin)
            })
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// A passage as someone selected it to share. Plain LaTeX renders as one
    /// equation. Text with `$...$` in it keeps its words, set in a serif, with
    /// each piece of math typeset in its line and `$$...$$` on a line of its
    /// own, wrapped to a readable width.
    static func passage(_ text: String, fontSize: CGFloat = 28, dark: Bool = false) -> Result<UIImage, Failure> {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        let pieces = Passage.pieces(of: text)
        guard pieces.contains(where: { if case .text = $0 { return false }; return true }) else {
            // No delimiters: the whole selection is the LaTeX.
            return image(latex: text, fontSize: fontSize, dark: dark)
        }

        let font = serif(size: fontSize)
        var layout = Passage.Layout(maxWidth: fontSize * 24, lineGap: fontSize * 0.4)
        for piece in pieces {
            switch piece {
            case .text(let words):
                for word in Passage.words(in: words) {
                    let string = NSAttributedString(string: word, attributes: [
                        .font: font, .foregroundColor: dark ? UIColor.white : UIColor.black,
                    ])
                    let width = string.size().width
                    layout.add(width: width, ascent: font.ascender, descent: -font.descender,
                               isSpace: word.allSatisfy(\.isWhitespace)) { origin in
                        string.draw(at: CGPoint(x: origin.x, y: origin.y))
                    }
                }
            case .newline:
                layout.breakLine()
            case .math(let source, let display):
                switch math(source, fontSize: fontSize, display: display, dark: dark) {
                case .success(let piece):
                    if display { layout.breakLine() }
                    layout.add(width: piece.width, ascent: piece.ascent, descent: piece.descent,
                               centred: display) { origin in
                        piece.image.draw(at: origin)
                    }
                    if display { layout.breakLine() }
                case .failure(.parse(let message)):
                    return .failure(.parse("\(message) in \(source)"))
                case .failure(.empty):
                    break
                }
            }
        }
        let size = layout.size
        guard size.width > 0, size.height > 0 else { return .failure(.empty) }
        return .success(card(size: size, fontSize: fontSize, dark: dark) { origin in
            layout.draw(at: origin)
        })
    }

    /// Puts the image on the clipboard as a JPEG, so apps paste it as a photo.
    static func copy(_ image: UIImage) {
        guard let data = jpeg(image) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: UTType.jpeg.identifier)
    }

    static func jpeg(_ image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.95)
    }

    /// The image as a JPEG file, for sharing and for Messages, which take
    /// files rather than images.
    static func jpegFile(_ image: UIImage, name: String = "equation") -> URL? {
        guard let data = jpeg(image) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".jpg")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    /// `$x^2$`, `$$x^2$$`, `\(x^2\)` and `\[x^2\]` all render as `x^2`.
    static func stripDelimiters(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")]
        where s.hasPrefix(open) && s.hasSuffix(close) && s.count >= open.count + close.count {
            s = String(s.dropFirst(open.count).dropLast(close.count))
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Pieces

    private struct Typeset {
        let image: UIImage
        let ascent: CGFloat
        let descent: CGFloat
        var width: CGFloat { image.size.width }
    }

    private static func math(_ source: String, fontSize: CGFloat, display: Bool,
                             dark: Bool) -> Result<Typeset, Failure> {
        // MathImage, not MTMathUILabel's layer: the label's drawing assumes a
        // flipped context, and rendering its layer into an image turned every
        // equation upside down.
        var math = MathImage(latex: source, fontSize: fontSize, textColor: dark ? .white : .black,
                             labelMode: display ? .display : .text, textAlignment: .left)
        let (error, rendered, info) = math.asImage()
        if let error { return .failure(.parse(error.localizedDescription)) }
        guard let rendered, rendered.size.width > 0, rendered.size.height > 0 else {
            return .failure(.empty)
        }
        // The image is as tall as the math, with the baseline its descent up
        // from the bottom.
        let descent = info?.descent ?? 0
        return .success(Typeset(image: rendered, ascent: rendered.size.height - descent, descent: descent))
    }

    private static func serif(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Black on white, or white on the dark grey of a dark-mode chat, with a
    /// margin of about half the font size.
    private static func card(size: CGSize, fontSize: CGFloat, dark: Bool,
                             draw: (CGPoint) -> Void) -> UIImage {
        let padding = fontSize * 0.6
        let total = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 3
        return UIGraphicsImageRenderer(size: total, format: format).image { context in
            (dark ? UIColor(white: 0.11, alpha: 1) : UIColor.white).setFill()
            context.fill(CGRect(origin: .zero, size: total))
            draw(CGPoint(x: padding, y: padding))
        }
    }
}

/// Splitting a passage into text and math, and setting it in lines.
enum Passage {

    enum Piece: Equatable {
        case text(String)
        case math(String, display: Bool)
        case newline
    }

    /// Text and math in order. `\$` is a dollar sign, and a delimiter that is
    /// never closed is left as text.
    static func pieces(of text: String) -> [Piece] {
        var pieces: [Piece] = []
        var plain = ""
        var rest = Substring(text)

        func flush() {
            for (index, line) in plain.components(separatedBy: "\n").enumerated() {
                if index > 0 { pieces.append(.newline) }
                if !line.isEmpty { pieces.append(.text(line)) }
            }
            plain = ""
        }

        while !rest.isEmpty {
            if rest.hasPrefix("\\$") {
                plain += "$"
                rest = rest.dropFirst(2)
                continue
            }
            var matched = false
            for (open, close, display) in [("$$", "$$", true), ("\\[", "\\]", true),
                                           ("$", "$", false), ("\\(", "\\)", false)]
            where rest.hasPrefix(open) {
                let body = rest.dropFirst(open.count)
                guard let end = body.range(of: close) else { break }
                flush()
                let source = body[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !source.isEmpty { pieces.append(.math(source, display: display)) }
                rest = body[end.upperBound...]
                matched = true
                break
            }
            if !matched {
                plain.append(rest.removeFirst())
            }
        }
        flush()
        return pieces
    }

    /// Words and the spaces between them, as separate pieces, so a line can
    /// break at any space.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            if !current.isEmpty, character.isWhitespace != current.last!.isWhitespace {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Lines of pieces sharing a baseline, filled up to a width.
    struct Layout {
        struct Item {
            var x: CGFloat
            let width: CGFloat
            let ascent: CGFloat
            let descent: CGFloat
            let draw: (CGPoint) -> Void
        }

        struct Line {
            var items: [Item] = []
            var width: CGFloat = 0
            var centred = false
            var ascent: CGFloat { items.map(\.ascent).max() ?? 0 }
            var descent: CGFloat { items.map(\.descent).max() ?? 0 }
        }

        let maxWidth: CGFloat
        let lineGap: CGFloat
        private(set) var lines: [Line] = [Line()]

        init(maxWidth: CGFloat, lineGap: CGFloat) {
            self.maxWidth = maxWidth
            self.lineGap = lineGap
        }

        mutating func breakLine() {
            if !(lines.last?.items.isEmpty ?? true) { lines.append(Line()) }
        }

        mutating func add(width: CGFloat, ascent: CGFloat, descent: CGFloat, isSpace: Bool = false,
                          centred: Bool = false, draw: @escaping (CGPoint) -> Void) {
            if lines[lines.count - 1].width + width > maxWidth, !lines[lines.count - 1].items.isEmpty {
                if isSpace { return }
                lines.append(Line())
            }
            if isSpace, lines[lines.count - 1].items.isEmpty { return }
            var line = lines[lines.count - 1]
            line.items.append(Item(x: line.width, width: width, ascent: ascent, descent: descent, draw: draw))
            line.width += width
            line.centred = centred
            lines[lines.count - 1] = line
        }

        private var filled: [Line] { lines.filter { !$0.items.isEmpty } }

        var size: CGSize {
            let lines = filled
            let height = lines.reduce(0) { $0 + $1.ascent + $1.descent }
                + lineGap * CGFloat(max(lines.count - 1, 0))
            return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
        }

        func draw(at origin: CGPoint) {
            let width = size.width
            var y = origin.y
            for line in filled {
                let baseline = y + line.ascent
                let indent = line.centred ? (width - line.width) / 2 : 0
                for item in line.items {
                    item.draw(CGPoint(x: origin.x + indent + item.x, y: baseline - item.ascent))
                }
                y = baseline + line.descent + lineGap
            }
        }
    }
}
