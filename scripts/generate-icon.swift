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
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    let inset = CGFloat(pixels) * 0.055
    let background = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2),
        xRadius: CGFloat(pixels) * 0.22,
        yRadius: CGFloat(pixels) * 0.22
    )
    NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.94, alpha: 1).setFill()
    background.fill()

    let boxRect = NSRect(
        x: CGFloat(pixels) * 0.22,
        y: CGFloat(pixels) * 0.22,
        width: CGFloat(pixels) * 0.56,
        height: CGFloat(pixels) * 0.50
    )
    let box = NSBezierPath(roundedRect: boxRect, xRadius: CGFloat(pixels) * 0.055, yRadius: CGFloat(pixels) * 0.055)
    NSColor.white.setFill()
    box.fill()

    NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.94, alpha: 1).setStroke()
    let seam = NSBezierPath()
    seam.lineWidth = max(1, CGFloat(pixels) * 0.025)
    seam.move(to: NSPoint(x: boxRect.minX, y: boxRect.maxY - boxRect.height * 0.28))
    seam.line(to: NSPoint(x: boxRect.maxX, y: boxRect.maxY - boxRect.height * 0.28))
    seam.stroke()

    let zipperX = CGFloat(pixels) * 0.50
    for index in 0..<6 {
        let y = CGFloat(pixels) * (0.30 + CGFloat(index) * 0.065)
        let tooth = NSBezierPath(roundedRect: NSRect(
            x: zipperX - CGFloat(pixels) * 0.025,
            y: y,
            width: CGFloat(pixels) * 0.05,
            height: CGFloat(pixels) * 0.032
        ), xRadius: CGFloat(pixels) * 0.008, yRadius: CGFloat(pixels) * 0.008)
        tooth.fill()
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("cannot render icon")
    }
    try png.write(to: output.appendingPathComponent(name))
}

