// chart <out.png>: the sample image Tools/screenshots.sh draws with ImageMagick, a "Weekly
// builds" bar chart, 860x520, drawn with AppKit.

import AppKit

let width = 860, height = 520
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// ImageMagick's coordinates: origin at the top left.
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)

func color(_ hex: String) -> NSColor {
    let value = Int(hex.dropFirst(), radix: 16)!
    return NSColor(deviceRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                   blue: CGFloat(value & 255) / 255, alpha: 1)
}

func text(_ string: String, x: CGFloat, baseline: CGFloat, size: CGFloat, hex: String) {
    let font = NSFont.systemFont(ofSize: size)
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color(hex)])
    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform()
    flip.translateX(by: x, yBy: baseline)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    attributed.draw(at: NSPoint(x: 0, y: font.descender))
    NSGraphicsContext.restoreGraphicsState()
}

color("#fbfbfa").setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
text("Weekly builds", x: 40, baseline: 56, size: 26, hex: "#222222")
text("Successful builds per day", x: 40, baseline: 84, size: 15, hex: "#666666")
color("#dddddd").setStroke()
for y in [440, 340, 240, 140] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 40, y: y))
    line.line(to: NSPoint(x: 820, y: y))
    line.stroke()
}
let bars = [140, 190, 120, 260, 210, 70, 160]
let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
for (index, bar) in bars.enumerated() {
    let x = 80 + index * 105
    color("#3b6ea8").setFill()
    NSRect(x: x, y: 440 - bar, width: 75, height: bar).fill()
    text(days[index], x: CGFloat(x + 22), baseline: 468, size: 14, hex: "#555555")
}
NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
