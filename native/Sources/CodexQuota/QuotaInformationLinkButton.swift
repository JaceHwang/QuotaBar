import AppKit
import QuotaCore

@MainActor
final class QuotaInformationLinkButton: NSButton {
    private static let textHeight: CGFloat = 20
    // NSTextField's 20pt label cell leaves the glyph ink optically high in a
    // compact 32pt row. Keep the baseline correction in one place so the
    // title and trailing arrow stay aligned with the X mark.
    private static let opticalTextYOffset: CGFloat = 2.5

    private let destination: URL
    private let onActivate: (URL) -> Void
    private let iconView = QuotaInformationXMarkView()
    private let linkLabel: NSTextField
    private let arrowLabel = NSTextField(labelWithString: "↗")
    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isPressing = false

    init(
        frame frameRect: NSRect,
        entry: QuotaInformationEntry,
        onActivate: @escaping (URL) -> Void
    ) {
        destination = entry.destination
        self.onActivate = onActivate
        linkLabel = NSTextField(labelWithString: entry.title)
        super.init(frame: frameRect)

        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(activateLink)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        linkLabel.font = .systemFont(ofSize: 12, weight: .medium)
        linkLabel.textColor = .labelColor
        linkLabel.lineBreakMode = .byTruncatingTail
        linkLabel.maximumNumberOfLines = 1

        arrowLabel.font = .systemFont(ofSize: 12, weight: .medium)
        arrowLabel.textColor = .secondaryLabelColor
        arrowLabel.alignment = .center

        addSubview(iconView)
        addSubview(linkLabel)
        addSubview(arrowLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.link)
        setAccessibilityLabel(entry.accessibilityLabel)
        setAccessibilityHelp(entry.destination.absoluteString)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(x: 6, y: 4, width: 24, height: 24)
        arrowLabel.frame = CGRect(
            x: bounds.maxX - 22,
            y: textFrameOriginY,
            width: 16,
            height: Self.textHeight
        )
        linkLabel.frame = CGRect(
            x: 40,
            y: textFrameOriginY,
            width: max(0, arrowLabel.frame.minX - 46),
            height: Self.textHeight
        )
    }

    private var textFrameOriginY: CGFloat {
        bounds.midY - (Self.textHeight / 2) + Self.opticalTextYOffset
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, frame.contains(point) else {
            return nil
        }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView.needsDisplay = true
        updateAppearance()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressing = false
        updateAppearance()
    }

    @objc
    private func activateLink() {
        onActivate(destination)
    }

    private func updateAppearance() {
        let alpha: CGFloat
        if isPressing {
            alpha = 0.11
        } else if isPointerInside {
            alpha = 0.07
        } else {
            alpha = 0
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(alpha)
                .cgColor
        }
    }
}

@MainActor
private final class QuotaInformationXMarkView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let markBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let background = NSBezierPath(
            roundedRect: markBounds,
            xRadius: 6,
            yRadius: 6
        )
        NSColor.labelColor.setFill()
        background.fill()

        let text = "X" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.windowBackgroundColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(
                x: floor((bounds.width - size.width) / 2),
                y: floor((bounds.height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }
}
