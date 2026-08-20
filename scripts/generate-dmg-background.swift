#!/usr/bin/env swift
// Regenerates the installer DMG background committed at assets/dmg/background.tiff.
//
// Run from the repo root after changing anything here:
//   swift scripts/generate-dmg-background.swift
//
// The output is a 600x400pt canvas with 1x and 2x representations in one TIFF
// (Finder picks the right one per display). Icon slots match the AppleScript
// layout in release-mac.sh: Pulse.app centered at (150, 205), Applications at
// (450, 205), both in top-left-origin window coordinates.

import AppKit

let canvas = NSSize(width: 600, height: 400)

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
    // context instead would mirror the text drawing.
    func fromTop(_ y: CGFloat) -> CGFloat { canvas.height - y }

    let ink = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    let subtle = NSColor(calibratedRed: 0.52, green: 0.52, blue: 0.55, alpha: 1)
    let accent = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)

    NSGradient(
        starting: NSColor(calibratedWhite: 0.985, alpha: 1),
        ending: NSColor(calibratedWhite: 0.945, alpha: 1)
    )!.draw(in: NSRect(origin: .zero, size: canvas), angle: 90)

    // Wordmark: the ECG waveform from the app mark, then the name.
    let wave = NSBezierPath()
    wave.lineWidth = 3
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round
    let waveY = fromTop(66)
    let waveStart: CGFloat = 232
    wave.move(to: NSPoint(x: waveStart, y: waveY))
    wave.line(to: NSPoint(x: waveStart + 12, y: waveY))
    wave.line(to: NSPoint(x: waveStart + 19, y: waveY + 14))
    wave.line(to: NSPoint(x: waveStart + 29, y: waveY - 16))
    wave.line(to: NSPoint(x: waveStart + 37, y: waveY + 6))
    wave.line(to: NSPoint(x: waveStart + 42, y: waveY))
    wave.line(to: NSPoint(x: waveStart + 54, y: waveY))
    accent.setStroke()
    wave.stroke()

    func drawCentered(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat, topY: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: centerX - size.width / 2, y: fromTop(topY) - size.height),
            withAttributes: attributes
        )
    }

    drawCentered(
        "Pulse",
        font: .systemFont(ofSize: 27, weight: .semibold),
        color: ink,
        centerX: 316,
        topY: 46
    )
    drawCentered(
        "Drag Pulse to the Applications folder to install",
        font: .systemFont(ofSize: 12.5, weight: .regular),
        color: subtle,
        centerX: 300,
        topY: 96
    )

    // Arrow between the two icon slots.
    let arrowY = fromTop(205)
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: 245, y: arrowY))
    arrow.line(to: NSPoint(x: 355, y: arrowY))
    arrow.move(to: NSPoint(x: 341, y: arrowY - 11))
    arrow.line(to: NSPoint(x: 355, y: arrowY))
    arrow.line(to: NSPoint(x: 341, y: arrowY + 11))
    NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
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
