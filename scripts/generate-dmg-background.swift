#!/usr/bin/env swift
// Regenerates the installer DMG background committed at assets/dmg/background.tiff.
//
// Run from the repo root after changing anything here:
//   swift scripts/generate-dmg-background.swift
//
// The output is a 600x360pt canvas with 1x and 2x representations in one TIFF
// (Finder picks the right one per display). The icon slots this artwork is
// composed around live in the volume's .DS_Store, not here: Pulse.app centred
// at (150, 180) and Applications at (450, 180) in top-left-origin window
// coordinates, both 128pt. Change one and re-capture the other with
// scripts/capture-dmg-layout.sh, or the arrow will point at nothing.
//
// The artwork carries no words. Finder already labels both icons, so a title
// and a "drag to install" line would put the product's name on screen three
// times over and say what the arrow says. What is left is the brand's own
// mark: a pulse line, faint, and low enough to stay clear of the labels.

import AppKit

let canvas = NSSize(width: 600, height: 360)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width * scale),
        pixelsHigh: Int(canvas.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = canvas

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Layout constants are written in window coordinates (origin top-left, the
    // system the Finder icon positions use) and converted here: flipping the
    // context instead would mirror anything with a direction.
    func fromTop(_ y: CGFloat) -> CGFloat { canvas.height - y }

    let accent = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)

    // Cool white falling to a hint of the brand blue, rather than neutral grey.
    NSGradient(
        starting: NSColor(calibratedRed: 0.988, green: 0.991, blue: 0.996, alpha: 1),
        ending: NSColor(calibratedRed: 0.929, green: 0.945, blue: 0.972, alpha: 1)
    )!.draw(in: NSRect(origin: .zero, size: canvas), angle: 90)

    // The pulse line runs the full width below the icon row. At 13% alpha it
    // reads as texture rather than content, which is what keeps it from
    // competing with the two icons the window is actually about.
    let line = NSBezierPath()
    line.lineWidth = 2
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    let baseline = fromTop(300)
    line.move(to: NSPoint(x: 0, y: baseline))
    var x: CGFloat = 40
    while x < canvas.width {
        line.line(to: NSPoint(x: x + 26, y: baseline))
        line.line(to: NSPoint(x: x + 38, y: baseline + 20))
        line.line(to: NSPoint(x: x + 52, y: baseline - 24))
        line.line(to: NSPoint(x: x + 64, y: baseline + 9))
        line.line(to: NSPoint(x: x + 72, y: baseline))
        x += 150
    }
    line.line(to: NSPoint(x: canvas.width, y: baseline))
    accent.withAlphaComponent(0.13).setStroke()
    line.stroke()

    // The arrow spans the gap between the two icon slots, clear of both.
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let arrowY = fromTop(180)
    arrow.move(to: NSPoint(x: 258, y: arrowY))
    arrow.line(to: NSPoint(x: 342, y: arrowY))
    arrow.move(to: NSPoint(x: 333, y: arrowY - 9))
    arrow.line(to: NSPoint(x: 342, y: arrowY))
    arrow.line(to: NSPoint(x: 333, y: arrowY + 9))
    NSColor(calibratedWhite: 0.70, alpha: 1).setStroke()
    arrow.stroke()

    return rep
}

let outputDirectory = URL(fileURLWithPath: "assets/dmg", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var temporaryPNGs: [URL] = []
for scale: CGFloat in [1, 2] {
    let rep = render(scale: scale)
    let url = outputDirectory.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png")
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    temporaryPNGs.append(url)
}

// One TIFF holding both scales; Finder resolves per display.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck"] + temporaryPNGs.map(\.path)
    + ["-out", outputDirectory.appendingPathComponent("background.tiff").path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else {
    fatalError("tiffutil failed with status \(tiffutil.terminationStatus)")
}
for url in temporaryPNGs {
    try FileManager.default.removeItem(at: url)
}
print("Wrote assets/dmg/background.tiff")
