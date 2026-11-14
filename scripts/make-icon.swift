// Rasterises Draft's canonical transparent glass mark into the macOS iconset source.
// Keep the source artwork in docs/assets so the README, website and app use one brand asset.
import AppKit
let size = 1024.0
let source = URL(fileURLWithPath: "docs/assets/draft-icon.png")
guard let sourceImage = NSImage(contentsOf: source) else {
    fatalError("Missing canonical logo at \(source.path)")
}
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
sourceImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                 from: .zero, operation: .sourceOver, fraction: 1)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
