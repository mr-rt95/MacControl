//
//  make-icon.swift
//  Draws the MacControl app icon and writes Resources/AppIcon.icns.
//
//  Usage: swiftc Scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources/AppIcon.icns
//

import AppKit

/// Renders the icon at `pixels` × `pixels`.
func renderIcon(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the artwork fills ~80% of the canvas.
    let inset = size * 0.1
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.95, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.17, blue: 0.48, alpha: 1)])?.draw(in: path, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "gauge", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        guard let png = renderIcon(pixels: base * scale) else { fatalError("render failed") }
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png.write(to: URL(fileURLWithPath: iconset + "/" + name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", output]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
exit(task.terminationStatus)
