import AppKit
import Foundation

// Renders the app icon: a ghost glyph on a dark rounded-square canvas,
// matching the HUD's dark aesthetic. No external design tools required.
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: gen_icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = CommandLine.arguments[1]

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
NSColor.clear.set()
rect.fill(using: .copy)

let bgPath = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.13, green: 0.10, blue: 0.20, alpha: 1),
    ending: NSColor(calibratedRed: 0.04, green: 0.03, blue: 0.08, alpha: 1))
gradient?.draw(in: bgPath, angle: -90)

let emoji = "👻" as NSString
let font = NSFont.systemFont(ofSize: 620)
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let textSize = emoji.size(withAttributes: attrs)
let origin = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 - 30)
emoji.draw(at: origin, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
