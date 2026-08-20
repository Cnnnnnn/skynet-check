import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: prepare-app-icon.swift <source.png> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = 1024

guard let source = NSImage(contentsOf: sourceURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("Unable to prepare icon source\n", stderr)
    exit(1)
}

NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let tileBounds = NSRect(x: 92, y: 92, width: 840, height: 840)
let roundedTile = NSBezierPath(
    roundedRect: tileBounds,
    xRadius: 180,
    yRadius: 180
)
roundedTile.addClip()
source.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .copy,
    fraction: 1
)
context.flushGraphics()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode processed icon\n", stderr)
    exit(1)
}
try data.write(to: outputURL)
