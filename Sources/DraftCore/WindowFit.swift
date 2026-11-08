import Foundation
import CoreGraphics

/// Keeps a window frame inside the screen's visible area, with a margin and at most 85% of its height.
public func fitWindowFrame(_ frame: CGRect, in visible: CGRect, margin: CGFloat = 16) -> CGRect {
    var f = frame
    f.size.height = min(f.height, (visible.height * 0.85).rounded())
    f.size.width = min(f.width, visible.width - margin * 2)
    f.origin.x = min(max(f.minX, visible.minX + margin), visible.maxX - margin - f.width)
    f.origin.y = min(max(f.minY, visible.minY + margin), visible.maxY - margin - f.height)
    return f
}
