#!/usr/bin/env swift
//
//  generate-appicon.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Draws the AltTab app icon with pure AppKit/CoreGraphics (no external
//  dependencies) and writes every size the AppIcon.appiconset needs.
//  The motif mirrors what the app does: two overlapping windows with the
//  front one wearing the switcher's selection ring, on a Big Sur-style
//  gradient squircle. Geometry is parametric, so each size is drawn at its
//  exact pixel dimensions instead of downscaled from the master.
//
//  Usage: swift scripts/generate-appicon.swift [output-dir]
//         (default output: AltTab/AltTab/Assets.xcassets/AppIcon.appiconset)
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import AppKit

// MARK: - Palette

let gradientTop    = NSColor(srgbRed: 0.35, green: 0.62, blue: 1.00, alpha: 1.0) // azure
let gradientBottom = NSColor(srgbRed: 0.27, green: 0.18, blue: 0.79, alpha: 1.0) // indigo
let backWindowFill = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.34)
let frontWindowFill = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.97)
let titleBarFill   = NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0)
let contentBarA    = NSColor(srgbRed: 0.80, green: 0.84, blue: 0.91, alpha: 1.0)
let contentBarB    = NSColor(srgbRed: 0.86, green: 0.89, blue: 0.94, alpha: 1.0)
let trafficRed     = NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1.0)
let trafficYellow  = NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1.0)
let trafficGreen   = NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1.0)

// MARK: - Drawing (canvas-relative units; u = pixels per 1024-canvas unit)

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let u = CGFloat(pixels) / 1024.0
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * u, y: y * u, width: w * u, height: h * u)
    }

    // Squircle plate (824x824 grid inside the 1024 canvas, per Apple's template)
    // with the template's soft drop shadow baked in.
    let plate = NSBezierPath(roundedRect: r(100, 100, 824, 824),
                             xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24 * u
    shadow.shadowOffset = NSSize(width: 0, height: -12 * u)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.set()
    gradientBottom.setFill()
    plate.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: gradientTop, ending: gradientBottom)?
        .draw(in: plate, angle: -70)

    // Back window — frosted, up-left of center.
    let back = NSBezierPath(roundedRect: r(252, 448, 400, 296),
                            xRadius: 34 * u, yRadius: 34 * u)
    backWindowFill.setFill()
    back.fill()

    // Selection ring — the switcher's accent border around the front window.
    let ring = NSBezierPath(roundedRect: r(340, 240, 468, 358),
                            xRadius: 52 * u, yRadius: 52 * u)
    ring.lineWidth = 18 * u
    NSColor.white.setStroke()
    ring.stroke()

    // Front window — solid, down-right of center, inside the ring with a gap
    // of background gradient so the ring reads as a highlight.
    let frontRect = r(366, 266, 416, 306)
    let front = NSBezierPath(roundedRect: frontRect,
                             xRadius: 34 * u, yRadius: 34 * u)
    frontWindowFill.setFill()
    front.fill()

    // Title bar + traffic lights, clipped to the front window shape.
    NSGraphicsContext.current?.saveGraphicsState()
    front.addClip()
    titleBarFill.setFill()
    r(366, 502, 416, 70).fill()
    for (i, color) in [trafficRed, trafficYellow, trafficGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: r(366 + 34 + CGFloat(i) * 44, 524, 26, 26)).fill()
    }
    // Content hint bars.
    contentBarA.setFill()
    NSBezierPath(roundedRect: r(404, 410, 340, 30), xRadius: 15 * u, yRadius: 15 * u).fill()
    contentBarB.setFill()
    NSBezierPath(roundedRect: r(404, 344, 250, 30), xRadius: 15 * u, yRadius: 15 * u).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AltTab/AltTab/Assets.xcassets/AppIcon.appiconset"

try? FileManager.default.createDirectory(atPath: outputDir,
                                         withIntermediateDirectories: true)

// (filename, pixel size) — shared files cover the @1x/@2x overlaps.
let files: [(String, Int)] = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024),
]

for (name, pixels) in files {
    let rep = drawIcon(pixels: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(name)")
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try png.write(to: url)
    print("wrote \(url.path) (\(pixels)x\(pixels))")
}
