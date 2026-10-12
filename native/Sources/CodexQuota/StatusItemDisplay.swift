import AppKit
import QuotaCore

@MainActor
final class StatusItemDisplayPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var showsQuotaInformation: Bool {
        get { defaults.object(forKey: "standalone.status.showsQuota") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "standalone.status.showsQuota") }
    }
}

@MainActor
enum QuotaStatusItemImage {
    static func make(showQuotaInformation: Bool, text: String, theme: CodexInterfaceTheme) -> NSImage {
        if !showQuotaInformation { return menuIcon }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        let indicator = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.black
        ])
        // NSStatusBarButton positions multiline titles using its title baseline.
        // An image uses the system's vertically centered image rectangle instead.
        let textSize = indicator.size()
        let imageSize = NSSize(width: ceil(textSize.width) + 2, height: ceil(textSize.height))
        let image = NSImage(size: imageSize, flipped: false) { rect in
            indicator.draw(in: NSRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width, height: textSize.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
    // Resolution-independent alpha mask: AppKit supplies the menu bar tint.
    private static let menuIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.8, startAngle: 130, endAngle: 430)
            ring.lineWidth = 2.3; ring.lineCapStyle = .round; ring.stroke()
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 3.5, y: 6.5))
            wave.curve(to: NSPoint(x: 14.4, y: 8), controlPoint1: NSPoint(x: 7, y: 3), controlPoint2: NSPoint(x: 10, y: 10))
            wave.curve(to: NSPoint(x: 3.5, y: 6.5), controlPoint1: NSPoint(x: 13, y: 1.5), controlPoint2: NSPoint(x: 5, y: 1.5))
            wave.close(); wave.fill()
            NSBezierPath(ovalIn: NSRect(x: 5.3, y: 10.4, width: 1.8, height: 1.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.8, y: 11.2, width: 1.8, height: 1.8)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

}
