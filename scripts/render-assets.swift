// Renders PipSqueak's app icon and DMG background into PNGs / .icns.
// Run via: swift scripts/render-assets.swift
//
// Outputs:
//   PipSqueak/Resources/Assets.xcassets/AppIcon.appiconset/  (full appiconset)
//   build/dmg-assets/background.png                          (1x, 660x440)
//   build/dmg-assets/background@2x.png                       (2x, 1320x880)
//   build/dmg-assets/VolumeIcon.icns                         (DMG volume icon)

import AppKit
import CoreGraphics
import Foundation

// MARK: - Drawing helpers

func makeBitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Use a coordinate space with origin at top-left (more natural for layout).
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

extension CGContext {
    func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func fillLinearGradient(in rect: CGRect, colors: [CGColor], locations: [CGFloat], vertical: Bool = true) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
        saveGState()
        addRect(rect)
        clip()
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = vertical ? CGPoint(x: rect.minX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.minY)
        drawLinearGradient(grad, start: start, end: end, options: [])
        restoreGState()
    }
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    return CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// MARK: - App icon
//
// macOS app icon convention: art lives inside roughly an 824x824 area
// centered in a 1024x1024 canvas (so the OS-applied rounded mask leaves
// margin around the artwork).

func renderAppIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    return makeBitmap(width: size, height: size) { ctx in
        // Background rounded square with diagonal warm gradient (orange → pink).
        let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
        let radius = s * 0.225 // macOS Big Sur+ icon shape
        let bgPath = ctx.roundedRect(bgRect, radius: radius)

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let cs = CGColorSpaceCreateDeviceRGB()
        let bgGrad = CGGradient(
            colorsSpace: cs,
            colors: [rgb(255, 138, 76), rgb(244, 73, 137)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: s, y: s),
            options: []
        )
        ctx.restoreGState()

        // Subtle top highlight inside the rounded square.
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let highlightRect = CGRect(x: 0, y: 0, width: s, height: s * 0.55)
        ctx.fillLinearGradient(
            in: highlightRect,
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
            ],
            locations: [0, 1]
        )
        ctx.restoreGState()

        // Foreground: SF Symbol "bell.badge.fill" centered, drawn in white.
        // SF Symbols rasterize cleanly at any size and gives us a recognizable
        // alert/reminder motif without manual path math.
        let symbolPointSize = s * 0.55
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold, scale: .large)
        guard let symbol = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else {
            return
        }

        // Tint the symbol white.
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceIn)
            return true
        }

        // Draw the (un-flipped) NSImage into our flipped CGContext via
        // an NSGraphicsContext that knows how to handle the flip.
        let symbolRect = CGRect(
            x: (s - tinted.size.width) / 2,
            y: (s - tinted.size.height) / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsCtx

        // Soft shadow underneath for depth.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        shadow.shadowBlurRadius = s * 0.02
        shadow.set()

        tinted.draw(
            in: symbolRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - DMG background
//
// The window is roughly 660x440 logical. We render the background at 1x and 2x.
// Layout (logical px):
//   PipSqueak.app icon at (170, 220)
//   Applications symlink at (490, 220)
// Background draws title text at top, a wide right-pointing arrow connecting
// the two icon "slots", and "Drag to Applications" caption.

func renderDMGBackground(scale: CGFloat) -> CGImage {
    let logicalW: CGFloat = 660
    let logicalH: CGFloat = 440
    let pxW = Int(logicalW * scale)
    let pxH = Int(logicalH * scale)

    return makeBitmap(width: pxW, height: pxH) { ctx in
        ctx.scaleBy(x: scale, y: scale)

        // Background: subtle warm gradient like the icon, but lightened.
        let bgRect = CGRect(x: 0, y: 0, width: logicalW, height: logicalH)
        let cs = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(
            colorsSpace: cs,
            colors: [rgb(255, 250, 245), rgb(255, 235, 235)] as CFArray,
            locations: [0, 1]
        )!
        ctx.saveGState()
        ctx.addRect(bgRect)
        ctx.clip()
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: logicalH),
            options: []
        )
        ctx.restoreGState()

        // Title text near the top.
        let title = "Install PipSqueak"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor(red: 0.18, green: 0.10, blue: 0.20, alpha: 1),
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)

        // We're in a flipped context; NSString drawing handles that with a
        // graphics-context push + flip.
        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsCtx
        (title as NSString).draw(
            at: CGPoint(x: (logicalW - titleSize.width) / 2, y: 50),
            withAttributes: titleAttrs
        )
        NSGraphicsContext.restoreGraphicsState()

        // Subtitle / caption.
        let caption = "Drag the app to your Applications folder"
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(red: 0.35, green: 0.25, blue: 0.30, alpha: 0.85),
        ]
        let capSize = (caption as NSString).size(withAttributes: captionAttrs)
        NSGraphicsContext.saveGraphicsState()
        let nsCtx2 = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsCtx2
        (caption as NSString).draw(
            at: CGPoint(x: (logicalW - capSize.width) / 2, y: 92),
            withAttributes: captionAttrs
        )
        NSGraphicsContext.restoreGraphicsState()

        // Big arrow between the two icon positions (220 → 490, vertical ~220).
        // Draw as a chunky stroked path with a triangular head.
        // Icons sit at x=170 (PipSqueak) and x=490 (Applications) with 128px
        // glyphs, so their inner edges are around x=234 and x=426. Keep the
        // arrow's head well clear of the Applications icon's left edge.
        let arrowY: CGFloat = 220
        let arrowStartX: CGFloat = 260
        let arrowEndX: CGFloat = 380
        let arrowColor = rgb(244, 73, 137, 0.85)

        ctx.setStrokeColor(arrowColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(10)
        ctx.move(to: CGPoint(x: arrowStartX, y: arrowY))
        ctx.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
        ctx.strokePath()

        // Arrow head triangle.
        ctx.setFillColor(arrowColor)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: arrowEndX + 30, y: arrowY))
        head.addLine(to: CGPoint(x: arrowEndX, y: arrowY - 22))
        head.addLine(to: CGPoint(x: arrowEndX, y: arrowY + 22))
        head.closeSubpath()
        ctx.addPath(head)
        ctx.fillPath()

        // Footer hint.
        let footer = "PipSqueak runs from your menu bar"
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(red: 0.45, green: 0.35, blue: 0.40, alpha: 0.75),
        ]
        let footSize = (footer as NSString).size(withAttributes: footerAttrs)
        NSGraphicsContext.saveGraphicsState()
        let nsCtx3 = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsCtx3
        (footer as NSString).draw(
            at: CGPoint(x: (logicalW - footSize.width) / 2, y: logicalH - 28),
            withAttributes: footerAttrs
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Main

let fm = FileManager.default
let here = URL(fileURLWithPath: fm.currentDirectoryPath)

let assetsRoot = here.appendingPathComponent("PipSqueak/Resources/Assets.xcassets")
let appIconSet = assetsRoot.appendingPathComponent("AppIcon.appiconset")
let dmgAssets = here.appendingPathComponent("build/dmg-assets")

try fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try fm.createDirectory(at: dmgAssets, withIntermediateDirectories: true)

// Asset Catalog top-level Contents.json
let topContents = """
{
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try topContents.write(
    to: assetsRoot.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

// macOS AppIcon set: 16, 32, 128, 256, 512 each at 1x and 2x
struct IconSpec {
    let size: Int
    let scale: Int
    var pixelSize: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let specs: [IconSpec] = [
    .init(size: 16, scale: 1), .init(size: 16, scale: 2),
    .init(size: 32, scale: 1), .init(size: 32, scale: 2),
    .init(size: 128, scale: 1), .init(size: 128, scale: 2),
    .init(size: 256, scale: 1), .init(size: 256, scale: 2),
    .init(size: 512, scale: 1), .init(size: 512, scale: 2),
]

print("Rendering app icons…")
for spec in specs {
    let img = renderAppIcon(size: spec.pixelSize)
    let url = appIconSet.appendingPathComponent(spec.filename)
    try writePNG(img, to: url)
    print("  \(spec.filename)  \(spec.pixelSize)x\(spec.pixelSize)")
}

// AppIcon.appiconset Contents.json
var imageEntries: [String] = []
for spec in specs {
    imageEntries.append("""
    {
      "idiom" : "mac",
      "size" : "\(spec.size)x\(spec.size)",
      "scale" : "\(spec.scale)x",
      "filename" : "\(spec.filename)"
    }
    """)
}
let iconsetContents = """
{
  "images" : [
    \(imageEntries.joined(separator: ",\n    "))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try iconsetContents.write(
    to: appIconSet.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

// Also drop a 512x512 and 1024x1024 PNG into build/dmg-assets for the .icns
// volume icon (built via iconutil in build-dmg.sh).
let bigIcon1024 = renderAppIcon(size: 1024)
try writePNG(bigIcon1024, to: dmgAssets.appendingPathComponent("VolumeIcon-1024.png"))
let bigIcon512 = renderAppIcon(size: 512)
try writePNG(bigIcon512, to: dmgAssets.appendingPathComponent("VolumeIcon-512.png"))

print("Rendering DMG background…")
let bg1x = renderDMGBackground(scale: 1)
let bg2x = renderDMGBackground(scale: 2)
try writePNG(bg1x, to: dmgAssets.appendingPathComponent("background.png"))
try writePNG(bg2x, to: dmgAssets.appendingPathComponent("background@2x.png"))

print("Done.")
