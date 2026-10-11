import AppKit

enum QuotaChromeStyle {
    static let separatorLineWidth: CGFloat = 1
    static let cardBorderLineWidth: CGFloat = 0
    static let separatorAlpha: CGFloat = 0.28

    static var separatorColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(separatorAlpha)
    }
}

@MainActor
final class QuotaCardMaterialView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    override var isOpaque: Bool { false }

    func shadowOpacity(for appearanceName: NSAppearance.Name) -> Float {
        appearanceName == .darkAqua ? 0.08 : 0.03
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cardBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let card = NSBezierPath(
            roundedRect: cardBounds,
            xRadius: 17.5,
            yRadius: 17.5
        )
        let appearanceName = effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        )
        let fill: NSColor
        if appearanceName == .darkAqua {
            fill = NSColor(calibratedWhite: 0.09, alpha: 0.98)
        } else {
            fill = .white
        }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(
            CGFloat(shadowOpacity(for: appearanceName ?? .aqua))
        )
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 8
        shadow.set()
        fill.setFill()
        card.fill()
        if QuotaChromeStyle.cardBorderLineWidth > 0 {
            QuotaChromeStyle.separatorColor.setStroke()
            card.lineWidth = QuotaChromeStyle.cardBorderLineWidth
            card.stroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
