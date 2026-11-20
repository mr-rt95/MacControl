//
//  make-dmg-background.swift
//  Draws the background of the installer window (an arrow from the app to the Applications folder).
//
//  Usage: swiftc Scripts/make-dmg-background.swift -o /tmp/make-dmg-background && /tmp/make-dmg-background Resources/dmg-background.png
//

import AppKit

let width = 660, height = 400
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Soft light background.
NSGradient(colors: [NSColor(calibratedWhite: 0.97, alpha: 1), NSColor(calibratedWhite: 0.88, alpha: 1)])?
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centeredAt y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let box = string.size()
    string.draw(at: NSPoint(x: (CGFloat(width) - box.width) / 2, y: y - box.height / 2))
}

draw("Перетащите MacControl в «Программы»", size: 22, weight: .semibold, color: NSColor(calibratedWhite: 0.15, alpha: 1), centeredAt: 340)
draw("Drag MacControl to the Applications folder", size: 14, weight: .regular, color: NSColor(calibratedWhite: 0.4, alpha: 1), centeredAt: 312)

// Arrow between the two icons (icons sit at x = 170 and x = 490, y = 200 from the top).
let arrowY = CGFloat(height) - 200
let arrow = NSBezierPath()
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 260, y: arrowY))
arrow.line(to: NSPoint(x: 395, y: arrowY))
arrow.move(to: NSPoint(x: 375, y: arrowY + 20))
arrow.line(to: NSPoint(x: 399, y: arrowY))
arrow.line(to: NSPoint(x: 375, y: arrowY - 20))
NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.95, alpha: 1).setStroke()
arrow.stroke()

draw("Если macOS предупреждает при первом запуске: правая кнопка ▸ «Открыть»", size: 12, weight: .regular,
     color: NSColor(calibratedWhite: 0.45, alpha: 1), centeredAt: 40)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: output))
