//
// Generates both of the app's icons from the artwork in Assets/.
//
//   swift Tools/make_icons.swift        (or: Scripts/make-icons.sh, which also
//                                        runs iconutil to produce the .icns)
//
// Two outputs, because the two icons are read in completely different places:
//
//   Assets/AppIcon.iconset/            the Finder / About / permission-prompt
//                                      icon, from Assets/app-icon.png
//   Sources/LaTeXSquigglyApp/MenuBarIconData.swift
//                                      the menu bar mark, from Assets/menu-icon.png
//
// The menu bar mark is embedded in source rather than bundled as a resource so
// that `swift run LaTeXSquigglyApp` shows the same icon as the built .app: this
// project is meant to be buildable with only the Command Line Tools, and a
// loose executable has no Resources directory to read from.
//
import AppKit
import Foundation

// MARK: Paths

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let menuSource = assets.appendingPathComponent("menu-icon.png")
let appSource = assets.appendingPathComponent("app-icon.png")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
let generated = root.appendingPathComponent("Sources/LaTeXSquigglyApp/MenuBarIconData.swift")

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("make_icons: " + message + "\n").utf8))
    exit(1)
}

func load(_ url: URL) -> CGImage {
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { die("cannot read \(url.lastPathComponent) — run this from the repository root") }
    return cg
}

/// A bitmap context in device RGB, origin bottom-left, ready to draw into.
func context(_ width: Int, _ height: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { die("cannot allocate a \(width)x\(height) context") }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:])
    else { die("cannot encode \(url.lastPathComponent)") }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    do { try data.write(to: url) } catch { die("cannot write \(url.path): \(error)") }
}

// MARK: Trimming

/// The bounding box of everything that is not fully transparent, in the image's
/// own pixel coordinates with the origin at the bottom left.
func opaqueBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { die("menu-icon.png is entirely transparent") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// The bounding box of everything that differs from the corner colour — the
/// wordmark inside its printed margin. Used to crop the padding the artwork
/// carries, so the mark fills the icon grid instead of floating in it.
func inkBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    let background = (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let distance = abs(Int(pixels[i]) - background.0)
                + abs(Int(pixels[i + 1]) - background.1)
                + abs(Int(pixels[i + 2]) - background.2)
            if distance > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX else { die("app-icon.png is a flat colour") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

// MARK: The menu bar mark

/// Rendered four times the 18 pt the status item draws at, so both 1x and 2x
/// displays get an exact integer downsample, and flattened to black: a template
/// image keeps only the alpha channel, and macOS supplies the colour — which is
/// what makes one file work on a light menu bar, a dark one, and a highlighted
/// status item.
let markHeight = 72

func makeMenuBarMark() -> Data {
    let source = load(menuSource)
    let bounds = opaqueBounds(source)
    let scale = CGFloat(markHeight) / bounds.height
    let width = max(1, Int((bounds.width * scale).rounded()))

    let ctx = context(width, markHeight)
    ctx.draw(source, in: CGRect(x: -bounds.minX * scale, y: -bounds.minY * scale,
                                width: CGFloat(source.width) * scale,
                                height: CGFloat(source.height) * scale))
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: markHeight))

    guard let image = ctx.makeImage() else { die("cannot render the menu bar mark") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:])
    else { die("cannot encode the menu bar mark") }
    return data
}

func writeMenuBarData(_ png: Data) {
    // 60 characters a line: long enough to keep the literal short, narrow
    // enough that the file stays readable in a terminal.
    let base64 = png.base64EncodedString()
    var lines: [String] = []
    var index = base64.startIndex
    while index < base64.endIndex {
        let end = base64.index(index, offsetBy: 60, limitedBy: base64.endIndex) ?? base64.endIndex
        lines.append("        " + base64[index..<end])
        index = end
    }

    let swift = """
        //
        // Generated by Tools/make_icons.swift from Assets/menu-icon.png.
        // Do not edit by hand; edit the artwork and regenerate.
        //
        //   Scripts/make-icons.sh
        //
        import Foundation

        enum MenuBarIconData {

            /// The mark trimmed to its bounding box and flattened to a black
            /// silhouette, \(markHeight) px tall — four times the point size the status
            /// item draws at, so 1x and 2x displays both get an exact integer
            /// downsample. Colour is discarded on purpose: as a template image
            /// it takes its colour from the menu bar, which is the only way one
            /// file reads correctly on a light bar, a dark bar and a
            /// highlighted status item.
            static let png = Data(base64Encoded: \"""
        \(lines.joined(separator: "\n"))
                \""", options: .ignoreUnknownCharacters)!
        }

        """
    do { try swift.write(to: generated, atomically: true, encoding: .utf8) }
    catch { die("cannot write \(generated.path): \(error)") }
}

// MARK: The app icon

/// macOS draws app icons on a shared grid: the artwork lives inside a rounded
/// square that fills 824 of the canvas's 1024 points, and the margin around it
/// is where the shadow goes. Full-bleed artwork ignoring the grid is the thing
/// that makes an icon look pasted in among the system's own.
let bodyRatio: CGFloat = 824.0 / 1024.0

/// The corner is a superellipse, not a circular round-rect: |x|^n + |y|^n = 1
/// with n = 5 is close enough to Apple's continuous corner that the difference
/// is invisible at every size an icon is actually seen.
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720

    for step in 0...steps {
        let t = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let c = cos(t), s = sin(t)
        let x = cx + a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = cy + b * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// The artwork cropped square around the wordmark, leaving it filling this much
/// of the width. The source PNG carries a wide printed margin of its own; kept
/// as-is the wordmark would shrink twice, once for its own margin and again for
/// the icon grid's.
let markFill: CGFloat = 0.76

func croppedArtwork() -> CGImage {
    let source = load(appSource)
    let ink = inkBounds(source)
    let side = min(CGFloat(source.width), CGFloat(source.height), ink.width / markFill)

    // Centred on the wordmark, then pushed back inside the artwork if that
    // would have run off an edge.
    var x = ink.midX - side / 2
    var y = ink.midY - side / 2
    x = min(max(x, 0), CGFloat(source.width) - side)
    y = min(max(y, 0), CGFloat(source.height) - side)

    guard let cropped = source.cropping(to: CGRect(x: x.rounded(), y: y.rounded(),
                                                   width: side.rounded(), height: side.rounded()))
    else { die("cannot crop app-icon.png") }
    return cropped
}

func renderAppIcon(_ artwork: CGImage, side: Int) -> CGImage {
    let ctx = context(side, side)
    let canvas = CGFloat(side)
    let body = (canvas * bodyRatio).rounded()
    let rect = CGRect(x: ((canvas - body) / 2).rounded(), y: ((canvas - body) / 2).rounded(),
                      width: body, height: body)
    let path = squirclePath(in: rect)

    // The artwork's background is nearly white, so without a shadow the icon
    // loses its edge against a white Finder window.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.008),
                  blur: canvas * 0.022,
                  color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(artwork, in: rect)
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { die("cannot render the \(side) px app icon") }
    return image
}

/// Every size iconutil expects. The @2x files are separate renders rather than
/// copies of the same pixels at another name: 32 px drawn as 32 px is sharper
/// than 32 px downsampled from 1024.
let iconsetSizes: [(name: String, side: Int)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024),
]

// MARK: Run

let png = makeMenuBarMark()
writeMenuBarData(png)
print("menu bar mark: \(png.count) bytes -> Sources/LaTeXSquigglyApp/MenuBarIconData.swift")

try? FileManager.default.removeItem(at: iconset)
let artwork = croppedArtwork()
for (name, side) in iconsetSizes {
    writePNG(renderAppIcon(artwork, side: side), to: iconset.appendingPathComponent(name))
}
print("app icon: \(iconsetSizes.count) sizes -> Assets/AppIcon.iconset")
