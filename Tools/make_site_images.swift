//
// Builds the site's images from the artwork in Assets/.
//
//   swift Tools/make_site_images.swift
//
// Writes into docs/assets/:
//
//   wordmark.png   alpha mask of the wordmark, coloured in CSS
//   mark.png       alpha mask of the LS mark, likewise
//   favicon.png    the app icon, from the same iconset the bundle uses
//   og-card.png    the picture that appears when the link is pasted somewhere
//
// The two marks are masks rather than pictures so the page can ink them for
// whichever theme the reader is in — one file, both grounds. Everything else
// on the site is CSS, so these four are the whole image budget.
//
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/assets")

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("make_site_images: " + message + "\n").utf8))
    exit(1)
}

func load(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { die("cannot read \(path) — run this from the repository root") }
    return cg
}

/// Straight RGBA bytes, origin top-left, for reading pixels back.
func samples(_ image: CGImage) -> ([UInt8], Int, Int) {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (bytes, w, h)
}

func writePNG(_ rep: NSBitmapImageRep, _ name: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else { die("cannot encode \(name)") }
    let url = out.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    do { try data.write(to: url) } catch { die("cannot write \(url.path): \(error)") }
    print("docs/assets/\(name): \(rep.pixelsWide)x\(rep.pixelsHigh), \(data.count) bytes")
}

// MARK: Coverage

/// How much ink is at each pixel, 0...1, and the box the ink sits in.
///
/// - Parameter keyingPaper: true for the wordmark, which is printed on a flat
///   colour rather than on transparency. The paper is not perfectly even, so
///   the ramp starts above the noise: without a floor every background pixel
///   gets a sliver of ink and the mark ends up sitting in a faint box.
func coverage(of image: CGImage, keyingPaper: Bool) -> (values: [Double], w: Int, h: Int, box: CGRect) {
    let (bytes, w, h) = samples(image)
    let paper = (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]))

    var values = [Double](repeating: 0, count: w * h)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let inked: Bool
            if keyingPaper {
                let distance = abs(Double(bytes[i]) - paper.0)
                    + abs(Double(bytes[i + 1]) - paper.1)
                    + abs(Double(bytes[i + 2]) - paper.2)
                values[y * w + x] = min(1, max(0, (distance - 28) / 62))
                inked = distance > 40
            } else {
                values[y * w + x] = Double(bytes[i + 3]) / 255
                inked = bytes[i + 3] > 8
            }
            if inked {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX else { die("found no ink in the artwork") }
    let pad = 4
    let x = max(0, minX - pad), y = max(0, minY - pad)
    return (values, w, h, CGRect(x: x, y: y,
                                 width: min(w - x, maxX - minX + 1 + pad * 2),
                                 height: min(h - y, maxY - minY + 1 + pad * 2)))
}

/// Coverage as a grey CGImage, so Core Graphics can resample it for us.
func greyImage(_ values: [Double], _ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let plane = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    for i in 0..<(w * h) { plane[i] = UInt8(values[i] * 255) }
    return ctx.makeImage()!
}

func resampledCoverage(_ image: CGImage, width: Int) -> ([UInt8], Int) {
    let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    var bytes = [UInt8](repeating: 0, count: width * height)
    bytes.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (bytes, height)
}

/// Writes coverage as a grey+alpha PNG for use as a CSS mask.
///
/// The grey plane is a constant, which the encoder flattens to nothing, so the
/// file is about a tenth of an RGBA copy. That constant is **white**: a browser
/// may resolve a mask by luminance rather than by alpha, and black ink at full
/// coverage is luminance zero, which would mask the element away entirely.
func writeMask(from path: String, keyingPaper: Bool, width: Int, as name: String) {
    let image = load(path)
    let (values, w, h, box) = coverage(of: image, keyingPaper: keyingPaper)
    let cropped = greyImage(values, w, h).cropping(to: box)!
    let (scaled, height) = resampledCoverage(cropped, width: width)

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 2, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceWhite,
                               bitmapFormat: .alphaNonpremultiplied,
                               bytesPerRow: width * 2, bitsPerPixel: 16)!
    let plane = rep.bitmapData!
    for i in 0..<(width * height) {
        plane[i * 2] = 255
        plane[i * 2 + 1] = scaled[i]
    }
    writePNG(rep, name)
}

// MARK: Run

writeMask(from: "Assets/app-icon.png", keyingPaper: true, width: 520, as: "wordmark.png")
writeMask(from: "Assets/menu-icon.png", keyingPaper: false, width: 120, as: "mark.png")

// The favicon is the app's own icon, so a tab and a Dock look like each other.
let iconset = "Assets/AppIcon.iconset/icon_256x256.png"
if FileManager.default.fileExists(atPath: iconset) {
    writePNG(NSBitmapImageRep(cgImage: load(iconset)), "favicon.png")
} else {
    print("skipping favicon.png — run Scripts/make-icons.sh first for Assets/AppIcon.iconset")
}

// The link card, at the 1.91:1 the scrapers crop to.
let cardW = 1200, cardH = 630
let card = CGContext(data: nil, width: cardW, height: cardH, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
card.interpolationQuality = .high
card.setFillColor(CGColor(red: 250/255, green: 247/255, blue: 238/255, alpha: 1))
card.fill(CGRect(x: 0, y: 0, width: cardW, height: cardH))

// Painted through the coverage rather than through the mask file: Core
// Graphics reads a clipping mask the other way up from CSS, and one artwork
// that means two opposite things is a trap worth not setting.
let art = load("Assets/app-icon.png")
let (values, w, h, box) = coverage(of: art, keyingPaper: true)
let inkW = 560.0, inkH = inkW * box.height / box.width
let inkRect = CGRect(x: (Double(cardW) - inkW) / 2, y: Double(cardH) / 2 - inkH / 2 + 14,
                     width: inkW, height: inkH)

let cropped = greyImage(values, w, h).cropping(to: box)!
let (cardCoverage, coverageH) = resampledCoverage(cropped, width: Int(inkW))
var inkBytes = [UInt8](repeating: 0, count: Int(inkW) * coverageH * 4)
for i in 0..<(Int(inkW) * coverageH) {
    let a = Double(cardCoverage[i]) / 255
    inkBytes[i*4]     = UInt8(226 * a)
    inkBytes[i*4 + 1] = UInt8(102 * a)
    inkBytes[i*4 + 2] = UInt8( 15 * a)
    inkBytes[i*4 + 3] = UInt8(255 * a)
}
inkBytes.withUnsafeMutableBytes { buffer in
    let ctx = CGContext(data: buffer.baseAddress, width: Int(inkW), height: coverageH,
                        bitsPerComponent: 8, bytesPerRow: Int(inkW) * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    card.draw(ctx.makeImage()!, in: inkRect)
}

let caption = "Type \\alpha, press space, get \u{03B1} \u{2014} in any app on your Mac."
let centred = NSMutableParagraphStyle(); centred.alignment = .center
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: card, flipped: false)
caption.draw(in: NSRect(x: 100, y: 92, width: Double(cardW) - 200, height: 60),
             withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .medium),
                .foregroundColor: NSColor(red: 92/255, green: 81/255, blue: 71/255, alpha: 1),
                .paragraphStyle: centred,
             ])
NSGraphicsContext.restoreGraphicsState()
writePNG(NSBitmapImageRep(cgImage: card.makeImage()!), "og-card.png")
