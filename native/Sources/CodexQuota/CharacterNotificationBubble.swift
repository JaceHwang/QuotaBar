import AppKit
import QuotaCore

private final class BubblePassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class BubbleRootView: NSView {
    var hover: ((Bool) -> Void)?
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
}
private final class BubbleSurfaceView: NSView {
    var dark = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = CGRect(x: 8, y: 0, width: bounds.width - 8, height: bounds.height)
        let fill = dark ? NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.21, alpha: 1) : .white
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
        let y = bounds.height * 0.54
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 9, y: y - 10)); tail.line(to: NSPoint(x: 0, y: y)); tail.line(to: NSPoint(x: 9, y: y + 10)); tail.close(); tail.fill()
    }
}
private final class BubbleArtworkView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class BubbleActionButton: NSButton {
    var messageID = ""
    var token: String?
    var primary = false
    var dark = false
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted }
    override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        if primary {
            NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.35, alpha: 1), ending: NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.25, alpha: 1))?.draw(in: path, angle: 90)
        } else {
            (dark ? NSColor(calibratedWhite: 0.23, alpha: 1) : NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)).setFill(); path.fill()
            (dark ? NSColor(calibratedWhite: 0.35, alpha: 1) : NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.94, alpha: 1)).setStroke(); path.lineWidth = 1; path.stroke()
        }
        if isHighlighted { NSColor.black.withAlphaComponent(0.12).setFill(); path.fill() }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            focus.lineWidth = 2; focus.stroke()
        }
        let size = attributedTitle.size()
        attributedTitle.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
enum NotificationCharacterArtwork: String { case attention, recovery, bank, neutral }
@MainActor final class CharacterNotificationBubble: NSObject {
    let panel: NSPanel = BubblePassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var onAction: ((String, String?) -> Void)?
    var onAcknowledge: ((String, String?) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    private var currentID = ""
    private(set) var isVisible = false
    override init() {
        super.init(); panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.level = .floating; panel.collectionBehavior = [.transient, .ignoresCycle]
    }
    func content(message: ExperienceNotification, dark: Bool, language: CodexDisplayLanguage, width: CGFloat, artwork: NotificationCharacterArtwork? = nil) -> NSView {
        currentID = message.id
        let copy = ExperienceCopy(language)
        let cardWidth = width - 112
        let textWidth = cardWidth - 40
        let titleFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        var displayBody = message.body
        if message.kind == .recovery || message.kind == .test {
            displayBody = displayBody.replacingOccurrences(of: "额度剩余", with: "剩余").replacingOccurrences(of: "額度剩餘", with: "剩餘").replacingOccurrences(of: "；", with: " · ")
        }
        func measured(_ text: String, _ font: NSFont, lines: Int) -> CGFloat {
            let line = ceil(font.ascender - font.descender + font.leading)
            let height = (text as NSString).boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
            return min(line * CGFloat(lines), max(line, ceil(height)))
        }
        let titleHeight = max(22, measured(message.title, titleFont, lines: 2))
        let bodyHeight = max(18, measured(displayBody, bodyFont, lines: 4))
        let bodyY = 42 + titleHeight + 4
        let actionsY = bodyY + bodyHeight + 12
        let height = actionsY + 44
        let root = BubbleRootView(frame: CGRect(x: 0, y: 0, width: width, height: height)); root.hover = { [weak self] in self?.onInteractionChanged?($0) }
        root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let card = BubbleSurfaceView(frame: CGRect(x: 104, y: 0, width: cardWidth + 8, height: height)); card.dark = dark; root.addSubview(card)
        let character = BubbleArtworkView(frame: CGRect(x: 0, y: height - 120, width: 104, height: 120))
        let asset = artwork?.rawValue ?? (message.kind == .bank ? "bank" : message.kind == .update ? "neutral" : "recovery")
        if let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Resources/NotificationCharacters"),
           let source = NSImage(contentsOf: url) {
            // Bound the illustration's visible footprint, excluding transparent export margins.
            // Keep the shared source PNG untouched for both native platforms.
            let crop: CGRect
            switch asset {
            case "attention": crop = CGRect(x: 159, y: 172, width: 906, height: 970)
            case "bank": crop = CGRect(x: 78, y: 169, width: 1040, height: 980)
            case "neutral": crop = CGRect(x: 272, y: 235, width: 710, height: 890)
            default: crop = CGRect(x: 256, y: 135, width: 957, height: 882)
            }
            if let pixels = source.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: crop) {
                character.image = NSImage(cgImage: pixels, size: crop.size)
            } else { character.image = source }
        }
        character.imageScaling = .scaleProportionallyUpOrDown; character.identifier = .init("notification.character"); root.addSubview(character)
        func label(_ text: String, font: NSFont, y: CGFloat, height: CGFloat, lines: Int = 1) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text); label.font = font
            label.maximumNumberOfLines = lines; label.usesSingleLineMode = false; label.cell?.wraps = true; label.cell?.isScrollable = false; label.lineBreakMode = .byWordWrapping; label.preferredMaxLayoutWidth = textWidth
            label.frame = CGRect(x: 28, y: y, width: textWidth, height: height)
            label.textColor = dark ? .white : NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.15, alpha: 1); label.toolTip = text; card.addSubview(label); return label
        }
        var category: String
        switch message.kind {
        case .recovery, .test: category = copy.text("Quota update", "额度更新", "額度更新")
        case .bank: category = copy.text("Bank reminder", "权益提醒", "權益提醒")
        case .update: category = copy.text("Software update", "软件更新", "軟體更新")
        }
        if artwork == .attention { category = copy.text("Quota reminder", "额度提醒", "額度提醒") }
        let amber = message.kind == .bank || artwork == .attention
        let tag = label(category, font: .systemFont(ofSize: 11, weight: .semibold), y: 15, height: 16)
        tag.textColor = dark ? (amber ? NSColor(calibratedRed: 1, green: 0.79, blue: 0.50, alpha: 1) : NSColor(calibratedRed: 0.82, green: 0.74, blue: 1, alpha: 1)) : (amber ? NSColor(calibratedRed: 0.52, green: 0.33, blue: 0.16, alpha: 1) : NSColor(calibratedRed: 0.37, green: 0.28, blue: 0.65, alpha: 1))
        let pillWidth = min(textWidth, ceil(tag.attributedStringValue.size().width) + 24)
        let pill = NSView(frame: CGRect(x: 28, y: 12, width: pillWidth, height: 22)); pill.wantsLayer = true; pill.layer?.cornerRadius = 11
        pill.layer?.backgroundColor = (amber ? NSColor(calibratedRed: 1, green: 0.94, blue: 0.85, alpha: dark ? 0.18 : 1) : NSColor(calibratedRed: 0.91, green: 0.86, blue: 1, alpha: dark ? 0.18 : 1)).cgColor
        card.addSubview(pill, positioned: .below, relativeTo: tag); tag.frame.origin.x += 12
        _ = label(message.title, font: titleFont, y: 42, height: titleHeight, lines: 2)
        let body = label(displayBody, font: bodyFont, y: bodyY, height: bodyHeight, lines: 4)
        body.textColor = dark ? NSColor(calibratedWhite: 0.78, alpha: 1) : NSColor(calibratedRed: 0.35, green: 0.41, blue: 0.53, alpha: 1)
        body.toolTip = message.body; body.setAccessibilityLabel(message.body)
        let title = message.kind == .bank ? copy.text("View Bank", "查看 Bank", "查看 Bank") : message.kind == .update ? copy.text("View update", "查看更新", "查看更新") : copy.text("View details", "查看详情", "查看詳情")
        let available = textWidth - 14
        let primaryWidth = floor(available * 1.2 / 2.2)
        func button(_ title: String, primary: Bool, x: CGFloat, width: CGFloat, action: Selector, identifier: String) {
            let button = BubbleActionButton(title: title, target: self, action: action)
            button.messageID = message.id; button.token = message.deliveryToken; button.primary = primary; button.dark = dark; button.isBordered = false
            button.frame = CGRect(x: x, y: actionsY, width: width, height: 32); button.font = .systemFont(ofSize: 13, weight: primary ? .semibold : .medium)
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: button.font!, .foregroundColor: primary ? NSColor.white : (dark ? NSColor.white : NSColor(calibratedRed: 0.35, green: 0.41, blue: 0.53, alpha: 1))])
            button.identifier = .init(identifier); card.addSubview(button)
        }
        button(title, primary: true, x: 28, width: primaryWidth, action: #selector(viewTapped(_:)), identifier: "notification.primary")
        button(copy.text("Got it", "知道了", "知道了"), primary: false, x: 28 + primaryWidth + 14, width: available - primaryWidth, action: #selector(acknowledgeTapped(_:)), identifier: "notification.acknowledge")
        root.setAccessibilityLabel(message.title + ". " + message.body)
        return root
    }
    func show(message: ExperienceNotification, anchor: CGRect, dark: Bool, language: CodexDisplayLanguage) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return false }
        let work = screen.visibleFrame
        let width = min(420, work.width - 16)
        guard width >= 340 else { return false }
        let normalizedAnchor = CGRect(x: anchor.minX, y: -anchor.maxY, width: anchor.width, height: anchor.height)
        let normalizedWork = CGRect(x: work.minX, y: -work.maxY, width: work.width, height: work.height)
        let view = content(message: message, dark: dark, language: language, width: width)
        guard let rect = NotificationBubbleLayout.place(anchor: normalizedAnchor, workArea: normalizedWork, size: view.frame.size) else { return false }
        panel.contentView = view
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.setFrame(CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height), display: true)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless(); isVisible = true
        if panel.alphaValue == 0 { NSAnimationContext.runAnimationGroup { c in c.duration = 0.15; panel.animator().alphaValue = 1 } }
        isVisible = panel.isVisible && panel.isOnActiveSpace
        if !isVisible { panel.orderOut(nil) }
        return isVisible
    }
    func contains(_ point: CGPoint) -> Bool { panel.isVisible && panel.frame.contains(point) }
    func dismiss() { panel.orderOut(nil); isVisible = false; onInteractionChanged?(false) }
    @objc private func viewTapped(_ sender: BubbleActionButton) { onAction?(sender.messageID, sender.token) }
    @objc private func acknowledgeTapped(_ sender: BubbleActionButton) { onAcknowledge?(sender.messageID, sender.token) }
}
