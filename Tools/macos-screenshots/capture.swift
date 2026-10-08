// capture <pid> <out.png>: the app's main window, with any popover or notice over it, on a
// transparent canvas with a drop shadow, like macOS's own window screenshots.
//
// screencapture -l given the id of the app's topmost window (the popover, when one is open)
// returns the main window with its child windows composited in, at the main window's size.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = Int(arguments[1]) else {
    FileHandle.standardError.write("usage: capture <pid> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0["kCGWindowOwnerPID"] as? Int) == pid && ($0["kCGWindowAlpha"] as? Double ?? 1) > 0 }
guard let top = windows.first?["kCGWindowNumber"] as? Int else {
    FileHandle.standardError.write("capture: no windows for pid \(pid)\n".data(using: .utf8)!)
    exit(1)
}

let raw = NSTemporaryDirectory() + "screenshottool-capture-\(pid).png"
let screencapture = Process()
screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
screencapture.arguments = ["-x", "-o", "-l\(top)", raw]
try screencapture.run()
screencapture.waitUntilExit()
guard let window = NSImage(contentsOfFile: raw), let windowRep = window.representations.first else {
    FileHandle.standardError.write("capture: screencapture failed (Screen Recording permission?)\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.removeItem(atPath: raw)

let scale = NSScreen.main?.backingScaleFactor ?? 1.0
let size = NSSize(width: CGFloat(windowRep.pixelsWide) / scale, height: CGFloat(windowRep.pixelsHigh) / scale)
let margin: CGFloat = 40
let canvas = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale),
                                 pixelsHigh: Int(canvas.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = canvas
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
window.draw(in: NSRect(x: margin, y: margin, width: size.width, height: size.height))
NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
