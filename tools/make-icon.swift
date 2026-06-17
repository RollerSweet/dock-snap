import AppKit
import Foundation

// Renders the DockSnap app icon at a given pixel size and returns PNG data.
// Concept: a keycap (the modifier you hold) sitting above a row of Dock tiles,
// one of which is "snapped"/highlighted — "hold a key, snap to a Dock app".
func renderIcon(size S: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: S, height: S)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // --- Background: rounded square with a blue→purple diagonal gradient ---
    let margin = 0.05 * S
    let bgRect = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let bgRadius = 0.2237 * bgRect.width
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: bgRadius, yRadius: bgRadius)

    let top = NSColor(srgbRed: 0.36, green: 0.56, blue: 1.00, alpha: 1)
    let bottom = NSColor(srgbRed: 0.42, green: 0.24, blue: 0.93, alpha: 1)
    NSGradient(colors: [top, bottom])?.draw(in: bgPath, angle: -55)

    // Subtle top gloss.
    bgPath.addClip()
    let gloss = NSBezierPath(ovalIn: NSRect(x: -0.2 * S, y: 0.45 * S, width: 1.4 * S, height: 0.9 * S))
    NSColor.white.withAlphaComponent(0.10).setFill()
    gloss.fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver

    // Reset clip for subsequent drawing.
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // --- Dock row: four rounded tiles near the bottom ---
    let tile: CGFloat = 0.105 * S
    let gap: CGFloat = 0.035 * S
    let count = 4
    let rowWidth = CGFloat(count) * tile + CGFloat(count - 1) * gap
    var tx = (S - rowWidth) / 2
    let ty = 0.165 * S
    for i in 0..<count {
        let r = NSRect(x: tx, y: ty, width: tile, height: tile)
        let p = NSBezierPath(roundedRect: r, xRadius: 0.26 * tile, yRadius: 0.26 * tile)
        // Third tile is the "snapped" one — fully opaque/brighter.
        NSColor.white.withAlphaComponent(i == 2 ? 0.95 : 0.45).setFill()
        p.fill()
        tx += tile + gap
    }

    // --- Keycap floating above the Dock ---
    let cap: CGFloat = 0.46 * S
    let cx = S / 2
    let cy = 0.575 * S
    let capRect = NSRect(x: cx - cap / 2, y: cy - cap / 2, width: cap, height: cap)
    let capRadius = 0.24 * cap

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -0.012 * S)
    shadow.shadowBlurRadius = 0.04 * S
    shadow.set()

    let capPath = NSBezierPath(roundedRect: capRect, xRadius: capRadius, yRadius: capRadius)
    let capTop = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    let capBottom = NSColor(srgbRed: 0.90, green: 0.92, blue: 0.97, alpha: 1)
    NSGradient(colors: [capTop, capBottom])?.draw(in: capPath, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Bevel highlight near the top of the keycap.
    let bevel = NSBezierPath(roundedRect: capRect.insetBy(dx: 0.08 * cap, dy: 0.08 * cap),
                             xRadius: 0.20 * cap, yRadius: 0.20 * cap)
    NSColor.white.withAlphaComponent(0.55).setStroke()
    bevel.lineWidth = 0.012 * S
    bevel.stroke()

    // --- The ⌥ glyph on the keycap ---
    let glyph = "\u{2325}"  // ⌥ Option symbol
    let font = NSFont.systemFont(ofSize: 0.5 * cap, weight: .bold)
    let glyphColor = NSColor(srgbRed: 0.38, green: 0.26, blue: 0.86, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: glyphColor]
    let str = glyph as NSString
    let textSize = str.size(withAttributes: attrs)
    let textRect = NSRect(
        x: cx - textSize.width / 2,
        y: cy - textSize.height / 2 + 0.005 * S,
        width: textSize.width, height: textSize.height
    )
    str.draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Generate the full .iconset.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    let data = renderIcon(size: spec.px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(spec.name)
    try! data.write(to: url)
    print("wrote \(spec.name) (\(Int(spec.px))px)")
}
