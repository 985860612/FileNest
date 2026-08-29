import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift output.iconset\n", stderr)
    exit(64)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    let p = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("cannot create icon canvas")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: p, height: p).fill()

    let inset = p * 0.055
    let background = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: p - inset * 2, height: p - inset * 2),
        xRadius: p * 0.22,
        yRadius: p * 0.22
    )
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.28, green: 0.64, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.30, blue: 0.82, alpha: 1)
    ])!
    backgroundGradient.draw(in: background, angle: -90)

    let highlight = NSBezierPath(
        roundedRect: NSRect(x: inset + p * 0.012, y: inset + p * 0.012,
                            width: p - (inset + p * 0.012) * 2,
                            height: p - (inset + p * 0.012) * 2),
        xRadius: p * 0.205,
        yRadius: p * 0.205
    )
    NSColor.white.withAlphaComponent(0.20).setStroke()
    highlight.lineWidth = max(1, p * 0.010)
    highlight.stroke()

    // Multiple documents rising from a tray represent archive, spreadsheet and file tools.
    let leftDocumentRect = NSRect(x: p * 0.22, y: p * 0.44, width: p * 0.34, height: p * 0.38)
    let leftDocument = NSBezierPath(
        roundedRect: leftDocumentRect,
        xRadius: p * 0.042,
        yRadius: p * 0.042
    )
    NSGraphicsContext.saveGraphicsState()
    let paperShadow = NSShadow()
    paperShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    paperShadow.shadowBlurRadius = p * 0.035
    paperShadow.shadowOffset = NSSize(width: 0, height: -p * 0.012)
    paperShadow.set()
    NSColor(calibratedRed: 0.75, green: 0.94, blue: 0.84, alpha: 1).setFill()
    leftDocument.fill()
    NSGraphicsContext.restoreGraphicsState()

    let rightDocumentRect = NSRect(x: p * 0.42, y: p * 0.47, width: p * 0.36, height: p * 0.39)
    let rightDocument = NSBezierPath(
        roundedRect: rightDocumentRect,
        xRadius: p * 0.042,
        yRadius: p * 0.042
    )
    NSGraphicsContext.saveGraphicsState()
    paperShadow.set()
    NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 1).setFill()
    rightDocument.fill()
    NSGraphicsContext.restoreGraphicsState()

    if pixels >= 64 {
        let green = NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.38, alpha: 0.88)
        green.setStroke()
        for index in 0..<3 {
            let y = p * (0.665 + CGFloat(index) * 0.045)
            let line = NSBezierPath()
            line.lineWidth = max(1, p * 0.014)
            line.move(to: NSPoint(x: p * 0.275, y: y))
            line.line(to: NSPoint(x: p * 0.465, y: y))
            line.stroke()
        }

        let blueMark = NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.96, alpha: 0.75)
        blueMark.setFill()
        for index in 0..<2 {
            let mark = NSBezierPath(roundedRect: NSRect(
                x: p * 0.475,
                y: p * (0.70 + CGFloat(index) * 0.055),
                width: p * (index == 0 ? 0.22 : 0.16),
                height: p * 0.020
            ), xRadius: p * 0.010, yRadius: p * 0.010)
            mark.fill()
        }
    }

    let trayRect = NSRect(x: p * 0.18, y: p * 0.18, width: p * 0.64, height: p * 0.40)
    let tray = NSBezierPath(roundedRect: trayRect, xRadius: p * 0.085, yRadius: p * 0.085)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = p * 0.050
    shadow.shadowOffset = NSSize(width: 0, height: -p * 0.018)
    shadow.set()
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    tray.fill()
    NSGraphicsContext.restoreGraphicsState()

    let trayGradient = NSGradient(colors: [
        NSColor.white,
        NSColor(calibratedRed: 0.83, green: 0.92, blue: 1.00, alpha: 1)
    ])!
    trayGradient.draw(in: tray, angle: -90)

    let lipRect = NSRect(x: p * 0.145, y: p * 0.49, width: p * 0.71, height: p * 0.13)
    let lip = NSBezierPath(roundedRect: lipRect, xRadius: p * 0.060, yRadius: p * 0.060)
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowBlurRadius = p * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -p * 0.010)
    shadow.set()
    NSColor.white.setFill()
    lip.fill()
    NSGraphicsContext.restoreGraphicsState()

    let blue = NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.90, alpha: 1)
    let slot = NSBezierPath(roundedRect: NSRect(x: p * 0.35, y: p * 0.325, width: p * 0.30, height: p * 0.072),
                            xRadius: p * 0.036, yRadius: p * 0.036)
    blue.setFill()
    slot.fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("cannot render icon")
    }
    try png.write(to: output.appendingPathComponent(name))
}
