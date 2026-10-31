// screenless app-icon generator — vector drawn with AppKit, saved as PNG
// at every macOS iconset size. Run via build.sh:  swiftc icon_gen.swift -o /tmp/icongen
import AppKit

func draw(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.06
    // deep navy squircle background
    let bg = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
        xRadius: s * 0.225, yRadius: s * 0.225)
    NSColor(calibratedRed: 0.106, green: 0.196, blue: 0.322, alpha: 1).setFill()
    bg.fill()

    // white phone outline (left of centre)
    let pw = s * 0.26, ph = s * 0.58
    let px = s * 0.42 - pw / 2
    let py = (s - ph) / 2
    let phone = NSBezierPath(
        roundedRect: NSRect(x: px, y: py, width: pw, height: ph),
        xRadius: pw * 0.20, yRadius: pw * 0.20)
    NSColor.white.setStroke()
    phone.lineWidth = s * 0.030
    phone.stroke()
    // dark "off screen" (the point of the product: phone display is off)
    let screen = NSBezierPath(
        roundedRect: NSRect(x: px + pw * 0.10, y: py + ph * 0.12, width: pw * 0.80, height: ph * 0.72),
        xRadius: pw * 0.10, yRadius: pw * 0.10)
    NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
    screen.fill()

    // radio arcs (wireless link) reaching to the right
    NSColor(calibratedWhite: 1.0, alpha: 1).setStroke()
    for r in [0.09, 0.16, 0.23] {   // radii as fraction of icon
        let left = s * 0.52
        let midY = s * 0.50
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: left, y: midY), radius: s * r,
                      startAngle: 290, endAngle: 70)
        arc.lineWidth = s * 0.026
        arc.lineCapStyle = .round
        arc.stroke()
    }
    // small laptop screen on the far right (the mirror target)
    let lw = s * 0.17, lh = s * 0.12
    let lx = s * 0.74, ly = s * 0.54
    let laptop = NSBezierPath(
        roundedRect: NSRect(x: lx - lw / 2, y: ly - lh / 2, width: lw, height: lh),
        xRadius: lw * 0.14, yRadius: lw * 0.14)
    NSColor.white.setStroke()
    laptop.lineWidth = s * 0.028
    laptop.stroke()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: lx - lw * 0.62, y: ly - lh / 2 - s * 0.020,
                              width: lw * 1.24, height: s * 0.016)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let rep = draw(size: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
print("iconset written to \(outDir)")
