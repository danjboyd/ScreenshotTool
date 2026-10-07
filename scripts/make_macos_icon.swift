// Makes the macOS app icon (Resources/ScreenshotToolIcon-macOS.png) from ScreenshotToolIcon.png.
//
// The source icon is the rounded square on an opaque background. macOS expects the shape on a
// transparent 1024px canvas, at the size of Apple's icon grid (824px, with a drop shadow), so cut
// the square out with a rounded mask and place it there.
//
// Usage: swift scripts/make_macos_icon.swift Resources/ScreenshotToolIcon.png Resources/ScreenshotToolIcon-macOS.png

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1]),
      let sourceRep = source.representations.first else {
    FileHandle.standardError.write("usage: make_macos_icon.swift <source.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

// The rounded square in the source, in pixels (measured; the source is 1024px).
let sourceSquare = NSRect(x: 141, y: 141, width: 742, height: 742)
let canvas = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    exit(1)
}
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let path = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

// Apple's grid: a soft shadow below the shape.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 20
shadow.set()
NSColor.black.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// The source square, flipped to AppKit's bottom-left origin, a little inside its edge so none of
// the old background shows at the corners.
let pixelHeight = CGFloat(sourceRep.pixelsHigh)
let scale = source.size.height / pixelHeight
let inset: CGFloat = 4
let from = NSRect(x: (sourceSquare.minX + inset) * scale,
                  y: (pixelHeight - sourceSquare.maxY + inset) * scale,
                  width: (sourceSquare.width - inset * 2) * scale,
                  height: (sourceSquare.height - inset * 2) * scale)
path.addClip()
source.draw(in: body, from: from, operation: .copy, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
