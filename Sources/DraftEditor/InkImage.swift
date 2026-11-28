import AppKit
import CoreImage

/// iPhone sketches (Continuity Camera › Add Sketch) arrive as a picture of ink on white paper.
/// `InkImage` lifts the ink off the paper (white becomes transparent, colours kept), trims the
/// picture to its strokes, and gives a lightened version for dark pages.
enum InkImage {
    /// The ink on a transparent background, trimmed to its strokes with a small margin.
    /// Returns nil when the picture has no ink (blank) or can't be read.
    static func lift(_ data: Data) -> Data? {
        guard let src = NSBitmapImageRep(data: data), let cg = src.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3]) / 255
                guard a > 0 else { continue }
                // Un-premultiply, then measure how far the pixel is from paper white.
                let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                // Paper white blended with ink colour C at coverage k: p = 1 - k(1 - C), so C = 1 - (1 - p) / k.
                let k = min(1, max(0, (0.94 - lum) / 0.55)), ink = k * a
                func col(_ v: Double) -> UInt8 { UInt8(min(1, max(0, 1 - (1 - v) / max(k, 0.0001))) * ink * 255) }
                px[i] = col(r); px[i + 1] = col(g); px[i + 2] = col(b); px[i + 3] = UInt8(ink * 255)
                if ink > 0.06 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= minX, maxY >= minY, let lifted = ctx.makeImage() else { return nil }
        let pad = max(8, min(w, h) / 40)
        // Rows in `px` run top-down, the same as CGImage cropping coordinates.
        let crop = CGRect(x: max(0, minX - pad), y: max(0, minY - pad), width: min(w, maxX + pad + 1) - max(0, minX - pad), height: min(h, maxY + pad + 1) - max(0, minY - pad))
        guard let trimmed = lifted.cropping(to: crop) else { return nil }
        let rep = NSBitmapImageRep(cgImage: trimmed)
        // Keep the original's point size per pixel, so the sketch isn't blown up on Retina.
        let ptPerPx = src.size.width / CGFloat(max(1, src.pixelsWide))
        rep.size = NSSize(width: CGFloat(trimmed.width) * ptPerPx, height: CGFloat(trimmed.height) * ptPerPx)
        return rep.representation(using: .png, properties: [:])
    }

    /// The same ink for dark pages: lightness inverted, hue kept (dark ink turns light, red stays red).
    static func forDarkPage(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let inverted = ci.applyingFilter("CIColorInvert").applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: Double.pi])
        let rep = NSCIImageRep(ciImage: inverted)
        let out = NSImage(size: image.size)
        out.addRepresentation(rep)
        return out
    }
}
