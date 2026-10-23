import Foundation
/// Coordinates normalized to top-left origin; native adapters convert screen coordinates.
public enum NotificationBubbleLayout {
    public static func place(anchor: CGRect, workArea: CGRect, size: CGSize) -> CGRect? {
        let inset = workArea.insetBy(dx: 8, dy: 8)
        guard size.width > 0, size.height > 0, size.width <= inset.width, size.height <= inset.height else { return nil }
        let x = min(max(anchor.minX, inset.minX), inset.maxX - size.width)
        let above = anchor.minY - 8 - size.height
        let below = anchor.maxY + 8
        if above >= inset.minY { return CGRect(origin: CGPoint(x: x, y: above), size: size) }
        if below + size.height <= inset.maxY { return CGRect(origin: CGPoint(x: x, y: below), size: size) }
        return nil
    }
}
