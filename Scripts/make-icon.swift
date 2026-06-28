#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — a purple squircle with a gold lock-shield.
// Run with:  swift Scripts/make-icon.swift
import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let size = img.size
    let out = NSImage(size: size)
    out.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: size))
    color.set()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func renderPNG(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background squircle (blue gradient).
    let inset = s * 0.045
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = (s - 2 * inset) * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.26, green: 0.53, blue: 0.96, alpha: 1.0),
        NSColor(srgbRed: 0.13, green: 0.32, blue: 0.74, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -90)

    // White lock-shield centered.
    let symbolColor = NSColor.white
    if let symbol = tintedSymbol("lock.shield.fill", pointSize: s * 0.52, color: symbolColor) {
        let ss = symbol.size
        let drawRect = NSRect(x: (s - ss.width) / 2, y: (s - ss.height) / 2, width: ss.width, height: ss.height)
        symbol.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconset entries: (filename, pixel size)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

var cache: [Int: Data] = [:]
for s in sizes { cache[s] = renderPNG(pixels: s) }

for (name, px) in entries {
    let data = cache[px] ?? renderPNG(pixels: px)
    try data.write(to: iconset.appendingPathComponent(name))
}

let resources = root.appendingPathComponent("Resources")
try? fm.createDirectory(at: resources, withIntermediateDirectories: true)
let icns = resources.appendingPathComponent("AppIcon.icns")

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
try? fm.removeItem(at: iconset)

print(proc.terminationStatus == 0 ? "Wrote \(icns.path)" : "iconutil failed (\(proc.terminationStatus))")
