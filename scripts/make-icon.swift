#!/usr/bin/env swift
// Draws the Mousip app icon and writes Resources/AppIcon.icns and Resources/icon.png.
//
//   swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    return NSImage(size: glyph.size, flipped: false) { rect in
        glyph.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func draw(_ image: NSImage, centeredAt center: CGPoint) {
    let size = image.size
    image.draw(in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height))
}

/// Draws the icon on a 1024×1024 canvas, following the macOS icon grid (824 pt tile, 100 pt margin).
func drawIcon() {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowOffset = CGSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x3A2FD6).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Indigo → violet background.
    NSGradient(colors: [color(0x2B5BFF), color(0x6A3DF0), color(0xA43BE0)])!.draw(in: shape, angle: -60)

    // Soft highlight on the upper half.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [.white.withAlphaComponent(0.18), .white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Three Spaces along the top: the middle one is the current one.
    let spaceSize = CGSize(width: 170, height: 112)
    for (index, x) in [272.0, 512.0, 752.0].enumerated() {
        let rect = CGRect(x: x - spaceSize.width / 2, y: 690, width: spaceSize.width, height: spaceSize.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
        (index == 1 ? NSColor.white.withAlphaComponent(0.95) : .white.withAlphaComponent(0.32)).setFill()
        path.fill()
    }

    // The mouse, with arrows for the tilt wheel.
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = .black.withAlphaComponent(0.25)
    glow.shadowOffset = CGSize(width: 0, height: -10)
    glow.shadowBlurRadius = 20
    glow.set()
    draw(symbol("computermouse.fill", pointSize: 380, weight: .regular, color: .white), centeredAt: CGPoint(x: 512, y: 390))
    NSGraphicsContext.restoreGraphicsState()

    let arrowColor = NSColor.white.withAlphaComponent(0.9)
    draw(symbol("chevron.left", pointSize: 130, weight: .heavy, color: arrowColor), centeredAt: CGPoint(x: 270, y: 390))
    draw(symbol("chevron.right", pointSize: 130, weight: .heavy, color: arrowColor), centeredAt: CGPoint(x: 754, y: 390))
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = CGSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

try render(pixels: 512).write(to: resources.appendingPathComponent("icon.png"))
print("✓ Resources/AppIcon.icns, Resources/icon.png")
