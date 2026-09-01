#!/usr/bin/env swift
// Rasterizes the full-bleed Pulse website mark into the PNG sizes the site
// actually serves. The SVG at website/public/pulse-icon.svg is the source of
// truth; these PNGs exist for favicon fallback, apple-touch-icon, and OAuth.
//
// Run from the repo root after changing the SVG:
//   swift scripts/generate-website-icons.swift
//
// Do not bake a squircle mask or macOS icon-grid padding into these files.
// Apple, browsers, and CSS apply rounding at display time.

import AppKit

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let publicDir = repoRoot.appendingPathComponent("website/public", isDirectory: true)
let svgURL = publicDir.appendingPathComponent("pulse-icon.svg")

guard let svg = NSImage(contentsOf: svgURL) else {
    fputs("failed to load \(svgURL.path)\n", stderr)
    exit(1)
}

struct Output {
    let name: String
    let pixels: Int
}

let outputs = [
    Output(name: "pulse-icon.png", pixels: 1024),
    Output(name: "apple-icon.png", pixels: 180),
    Output(name: "icon.png", pixels: 64),
]

func rasterize(pixels: Int) -> NSBitmapImageRep {
    let sourcePixels = 1024
    let source = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: sourcePixels,
        pixelsHigh: sourcePixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    source.size = NSSize(width: sourcePixels, height: sourcePixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: source)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true
    svg.draw(
        in: NSRect(x: 0, y: 0, width: sourcePixels, height: sourcePixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    if pixels == sourcePixels {
        return source
    }

    let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    scaled.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: source.cgImage!, size: NSSize(width: pixels, height: pixels))
        .draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
    NSGraphicsContext.restoreGraphicsState()
    return scaled
}

for output in outputs {
    let rep = rasterize(pixels: output.pixels)
    let url = publicDir.appendingPathComponent(output.name)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to encode \(output.name)\n", stderr)
        exit(1)
    }
    try data.write(to: url)
    fputs("wrote \(url.path) (\(output.pixels)×\(output.pixels))\n", stderr)
}
