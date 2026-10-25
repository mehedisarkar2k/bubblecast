import AppKit

// Draws the 1024 px app icon: a screen with a camera bubble and a red record dot.
let size = 1024.0
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.43, green: 0.36, blue: 0.97, alpha: 1),
           ending: NSColor(red: 0.20, green: 0.14, blue: 0.62, alpha: 1))!.draw(in: tilePath, angle: -90)

let screen = NSBezierPath(roundedRect: NSRect(x: 250, y: 360, width: 560, height: 390), xRadius: 52, yRadius: 52)
NSColor.white.withAlphaComponent(0.16).setFill()
screen.fill()
NSColor.white.withAlphaComponent(0.92).setStroke()
screen.lineWidth = 26
screen.stroke()

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
let bubbleRect = NSRect(x: 190, y: 180, width: 330, height: 330)
NSColor.white.setFill()
NSBezierPath(ovalIn: bubbleRect).fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: bubbleRect.insetBy(dx: 18, dy: 18)).addClip()
NSColor(red: 0.33, green: 0.26, blue: 0.85, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 296, y: 330, width: 118, height: 118)).fill()
NSBezierPath(ovalIn: NSRect(x: 230, y: 150, width: 250, height: 200)).fill()
NSGraphicsContext.restoreGraphicsState()

NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 668, y: 618, width: 150, height: 150)).fill()
NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 686, y: 636, width: 114, height: 114)).fill()
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render the icon")
}
try png.write(to: URL(fileURLWithPath: output))
