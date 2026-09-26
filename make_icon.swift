import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: S, height: S)
let clip = CGPath(roundedRect: rect, cornerWidth: 236, cornerHeight: 236, transform: nil)
ctx.addPath(clip)
ctx.clip()

let space = CGColorSpaceCreateDeviceRGB()
let colors = [
    NSColor(calibratedRed: 0.16, green: 0.33, blue: 0.95, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.42, green: 0.22, blue: 0.88, alpha: 1).cgColor
] as CFArray
let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 80, y: S - 80), end: CGPoint(x: S - 80, y: 80), options: [])

let glowSpace = CGColorSpaceCreateDeviceRGB()
let glowColors = [
    NSColor.white.withAlphaComponent(0.14).cgColor,
    NSColor.white.withAlphaComponent(0.0).cgColor
] as CFArray
let glow = CGGradient(colorsSpace: glowSpace, colors: glowColors, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 760, y: 780), startRadius: 0, endCenter: CGPoint(x: 760, y: 780), endRadius: 560, options: [])

func glyph(_ name: String, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) -> NSImage {
    let conf = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(.init(hierarchicalColor: color))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(conf)!
}

let display = glyph("display", 540, .white, .medium)
let dw: CGFloat = 580
display.draw(in: CGRect(x: 140, y: 250, width: dw, height: dw), from: .zero, operation: .sourceOver, fraction: 1)

let sun = glyph("sun.max.fill", 240, NSColor.systemYellow, .bold)
sun.draw(in: CGRect(x: 620, y: 600, width: 300, height: 300), from: .zero, operation: .sourceOver, fraction: 1)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_1024.png"))
print("icon rendered")
