// Draws Draft's original app icon: a folded paper sheet with an ink stroke on a dusk gradient.
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let r = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.42, blue: 0.94, alpha: 1), NSColor(srgbRed: 0.94, green: 0.55, blue: 0.45, alpha: 1)])!.draw(in: bg, angle: -60)
let sheet = NSBezierPath()
sheet.move(to: NSPoint(x: 300, y: 230)); sheet.line(to: NSPoint(x: 300, y: 790)); sheet.line(to: NSPoint(x: 610, y: 790))
sheet.line(to: NSPoint(x: 724, y: 676)); sheet.line(to: NSPoint(x: 724, y: 230)); sheet.close()
NSGraphicsContext.current?.saveGraphicsState()
let sh = NSShadow(); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -12); sh.shadowColor = NSColor.black.withAlphaComponent(0.25); sh.set()
NSColor(srgbRed: 1, green: 0.99, blue: 0.97, alpha: 1).setFill(); sheet.fill()
NSGraphicsContext.current?.restoreGraphicsState()
let fold = NSBezierPath(); fold.move(to: NSPoint(x: 610, y: 790)); fold.line(to: NSPoint(x: 610, y: 676)); fold.line(to: NSPoint(x: 724, y: 676)); fold.close()
NSColor(srgbRed: 0.88, green: 0.86, blue: 0.82, alpha: 1).setFill(); fold.fill()
let ink = NSBezierPath(); ink.lineWidth = 34; ink.lineCapStyle = .round
ink.move(to: NSPoint(x: 380, y: 600)); ink.curve(to: NSPoint(x: 640, y: 560), controlPoint1: NSPoint(x: 470, y: 660), controlPoint2: NSPoint(x: 560, y: 500))
NSColor(srgbRed: 0.36, green: 0.42, blue: 0.94, alpha: 1).setStroke(); ink.stroke()
for (y, w) in [(470.0, 260.0), (400.0, 300.0), (330.0, 200.0)] {
    let l = NSBezierPath(roundedRect: NSRect(x: 380, y: y, width: w, height: 22), xRadius: 11, yRadius: 11)
    NSColor(white: 0.2, alpha: 0.16).setFill(); l.fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
