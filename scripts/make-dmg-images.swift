//
// Builds the disk image's two pictures from the artwork in Assets/.
//
//   swift Tools/make_dmg_images.swift
//
// Writes into Assets/:
//
//   VolumeIcon.iconset/    the mounted volume's icon, from Assets/dmg_image.png
//                          (Scripts/make-icons.sh turns this into an .icns)
//   dmg-background.tiff    the window behind the two icons
//
// The background is drawn here rather than exported from a design tool for the
// same reason the coverage table is generated: the icon positions in
// Scripts/make-app.sh and the arrow between them have to agree, and two files
// that must agree should have one author. Change `layout` below and both the
// picture and the window follow.
//
// Two representations go into the TIFF, 1x and 2x at the same point size, so
// Finder has a crisp one to draw on a Retina display and the window measures
// the same on both.
//
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("make_dmg_images: " + message + "\n").utf8))
    exit(1)
}

// MARK: - The layout both the picture and the window are built from

/// Everything Scripts/make-app.sh also needs to know. Point units, origin at
/// the top left of the window's content area, which is how Finder counts.
enum Layout {
    static let width: CGFloat = 660
    static let height: CGFloat = 420

    static let iconSize: CGFloat = 128
    /// Centres of the two icons. The label sits under each one, so these are
    /// higher than the middle of the window.
    static let appCentre = CGPoint(x: 178, y: 196)
    static let applicationsCentre = CGPoint(x: 482, y: 196)
}

let cream = NSColor(srgbRed: 0.980, green: 0.969, blue: 0.933, alpha: 1)      // #FAF7EE
let blobOrange = NSColor(srgbRed: 0.949, green: 0.573, blue: 0.180, alpha: 1) // #F2922E
let inkOrange = NSColor(srgbRed: 0.910, green: 0.451, blue: 0.063, alpha: 1)  // #E87310

// MARK: - Drawing

/// One corner decoration: a soft organic blob hugging the corner, with three
/// short rays coming off it. Drawn for the top-left and then transformed, so
/// the two corners are the same shape rather than two hand-made ones.
func drawCornerDecoration(in context: CGContext, flipped: Bool) {
    context.saveGState()
    if flipped {
        context.translateBy(x: Layout.width, y: Layout.height)
        context.rotate(by: .pi)
    }

    let blob = NSBezierPath()
    blob.move(to: .init(x: 0, y: 0))
    blob.line(to: .init(x: 176, y: 0))
    blob.curve(to: .init(x: 120, y: 62), controlPoint1: .init(x: 168, y: 30),
               controlPoint2: .init(x: 146, y: 48))
    blob.curve(to: .init(x: 96, y: 128), controlPoint1: .init(x: 96, y: 76),
               controlPoint2: .init(x: 108, y: 106))
    blob.curve(to: .init(x: 0, y: 168), controlPoint1: .init(x: 78, y: 156),
               controlPoint2: .init(x: 42, y: 150))
    blob.close()

    context.setFillColor(blobOrange.cgColor)
    context.addPath(blob.cgPath)
    context.fillPath()

    // The rays, thrown clear of the blob along its diagonal. All three stay
    // outside the 128pt box an icon occupies: anything inside one is drawn and
    // then hidden, except for the corners, where it peeks out and reads as a
    // smudge.
    context.setStrokeColor(inkOrange.cgColor)
    context.setLineWidth(9)
    context.setLineCap(.round)
    for (start, end) in [(CGPoint(x: 196, y: 44), CGPoint(x: 232, y: 22)),
                         (CGPoint(x: 186, y: 92), CGPoint(x: 214, y: 108)),
                         (CGPoint(x: 84, y: 170), CGPoint(x: 96, y: 208))] {
        context.move(to: start)
        context.addLine(to: end)
    }
    context.strokePath()

    context.restoreGState()
}

/// The arrow between the two icons: a gently rising curve with a solid head,
/// drawn from the layout rather than positioned by eye.
func drawArrow(in context: CGContext) {
    let gap = Layout.applicationsCentre.x - Layout.appCentre.x
    let start = CGPoint(x: Layout.appCentre.x + gap * 0.30, y: Layout.appCentre.y + 6)
    let end = CGPoint(x: Layout.appCentre.x + gap * 0.68, y: Layout.appCentre.y - 6)
    let head: CGFloat = 21

    context.setStrokeColor(inkOrange.cgColor)
    context.setLineWidth(11)
    context.setLineCap(.round)
    context.move(to: start)
    context.addQuadCurve(to: CGPoint(x: end.x - head * 0.55, y: end.y),
                         control: CGPoint(x: (start.x + end.x) / 2, y: start.y + 16))
    context.strokePath()

    context.setFillColor(inkOrange.cgColor)
    context.move(to: CGPoint(x: end.x + head * 0.60, y: end.y - 1))
    context.addLine(to: CGPoint(x: end.x - head * 0.55, y: end.y - head * 0.52))
    context.addLine(to: CGPoint(x: end.x - head * 0.55, y: end.y + head * 0.52))
    context.closePath()
    context.fillPath()
}

/// One representation of the background at the given scale.
func background(scale: Int) -> NSBitmapImageRep {
    let pixelsWide = Int(Layout.width) * scale
    let pixelsHigh = Int(Layout.height) * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { die("cannot allocate the background bitmap") }
    // The point size is the same at both scales; only the pixels differ.
    rep.size = NSSize(width: Layout.width, height: Layout.height)

    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
        die("cannot draw into the background bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    // Finder counts from the top left; flipping here means every coordinate
    // above reads the same way as the ones make-app.sh hands to Finder.
    context.translateBy(x: 0, y: Layout.height)
    context.scaleBy(x: 1, y: -1)

    context.setFillColor(cream.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: Layout.width, height: Layout.height))

    drawCornerDecoration(in: context, flipped: false)
    drawCornerDecoration(in: context, flipped: true)
    drawArrow(in: context)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - The volume icon

/// Pads the artwork to a square, because an iconset is square and the source
/// is not. Padding rather than stretching: the box is a drawn object and
/// squashing it would show.
func squared(_ image: CGImage) -> CGImage {
    let side = max(image.width, image.height)
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { die("cannot allocate the volume icon canvas") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: (side - image.width) / 2,
                                   y: (side - image.height) / 2,
                                   width: image.width, height: image.height))
    guard let out = context.makeImage() else { die("cannot square the volume icon") }
    return out
}

func scaled(_ image: CGImage, to side: Int) -> Data {
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { die("cannot allocate a \(side)pt volume icon") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let out = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    else { die("cannot encode a \(side)pt volume icon") }
    return data
}

// MARK: - Run

let source = assets.appendingPathComponent("dmg_image.png")
guard let artwork = NSImage(contentsOf: source),
      let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { die("cannot read Assets/dmg_image.png — run this from the repository root") }

let square = squared(cg)
let iconset = assets.appendingPathComponent("VolumeIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
do { try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true) }
catch { die("cannot create \(iconset.path): \(error)") }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let data = scaled(square, to: points * scale)
        do { try data.write(to: iconset.appendingPathComponent(name)) }
        catch { die("cannot write \(name): \(error)") }
    }
}
print("Assets/VolumeIcon.iconset: 10 sizes from \(cg.width)x\(cg.height) artwork")

let picture = NSImage(size: NSSize(width: Layout.width, height: Layout.height))
picture.addRepresentation(background(scale: 1))
picture.addRepresentation(background(scale: 2))
// LZW, because this file is committed and flat colour compresses to almost
// nothing. Lossless, so the picture is the one that was drawn.
guard let tiff = picture.tiffRepresentation(using: .lzw, factor: 0) else {
    die("cannot encode the background")
}
let backgroundURL = assets.appendingPathComponent("dmg-background.tiff")
do { try tiff.write(to: backgroundURL) }
catch { die("cannot write \(backgroundURL.path): \(error)") }
print("Assets/dmg-background.tiff: \(Int(Layout.width))x\(Int(Layout.height)) pt at 1x and 2x, \(tiff.count) bytes")
