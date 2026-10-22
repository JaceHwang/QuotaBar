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
        let rect = bounds.insetBy(dx: 1, dy: 1)
        (dark ? NSColor(calibratedWhite: 0.14, alpha: 0.99) : NSColor(calibratedWhite: 1, alpha: 0.99)).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16); path.fill()
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.10).setStroke(); path.lineWidth = 0.7; path.stroke()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 1, y: 38)); tail.line(to: NSPoint(x: -7, y: 45)); tail.line(to: NSPoint(x: 1, y: 52)); tail.close()
        (dark ? NSColor(calibratedWhite: 0.14, alpha: 1) : NSColor.white).setFill(); tail.fill()
    }
}
private final class BubbleActionButton: NSButton { var messageID = ""; var token: String? }
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
    func content(message: ExperienceNotification, dark: Bool, language: CodexDisplayLanguage, width: CGFloat) -> NSView {
        currentID = message.id
        let copy = ExperienceCopy(language)
        let root = BubbleRootView(frame: CGRect(x: 0, y: 0, width: width, height: 180)); root.hover = { [weak self] in self?.onInteractionChanged?($0) }
        root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let card = BubbleSurfaceView(frame: CGRect(x: 48, y: 0, width: width - 48, height: 180)); card.dark = dark; root.addSubview(card)
        let character = QuotaMoodView(frame: CGRect(x: 0, y: 26, width: 40, height: 48)); character.dark = dark
        character.mood = message.kind == .recovery || message.kind == .test ? .recovered : .good
        character.stars = false; root.addSubview(character)
        if message.kind == .bank || message.kind == .update {
            let symbol = NSImageView(frame: CGRect(x: 25, y: 57, width: 18, height: 18))
            symbol.image = NSImage(systemSymbolName: message.kind == .bank ? "clock.fill" : "arrow.up.circle.fill", accessibilityDescription: nil)
            symbol.contentTintColor = dark ? .white : .darkGray; root.addSubview(symbol)
        }
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, height: CGFloat, lines: Int = 1) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight)
            label.maximumNumberOfLines = lines; label.usesSingleLineMode = false; label.cell?.wraps = true; label.cell?.isScrollable = false; label.lineBreakMode = .byWordWrapping; label.preferredMaxLayoutWidth = card.frame.width - 28
            label.frame = CGRect(x: 14, y: y, width: card.frame.width - 28, height: height)
            label.textColor = dark ? .white : NSColor(calibratedWhite: 0.12, alpha: 1); label.toolTip = text; card.addSubview(label); return label
        }
        let category: String
        switch message.kind {
        case .recovery: category = copy.text("Quota recovery", "额度恢复", "額度恢復")
        case .bank: category = copy.text("Bank reminder", "权益提醒", "權益提醒")
        case .update: category = copy.text("Software update", "软件更新", "軟體更新")
        case .test: category = copy.text("Example", "示例", "範例")
        }
        let tag = label(category, size: 10, weight: .medium, y: 12, height: 16); tag.textColor = message.kind == .recovery ? (dark ? .systemPurple : NSColor(calibratedRed: 0.4, green: 0.27, blue: 0.62, alpha: 1)) : (dark ? .systemOrange : NSColor(calibratedRed: 0.5, green: 0.32, blue: 0.12, alpha: 1))
        _ = label(message.title, size: 14, weight: .semibold, y: 34, height: 34, lines: 2)
        let body = label(message.body, size: 12, weight: .regular, y: 74, height: 60, lines: 4); body.textColor = dark ? NSColor(calibratedWhite: 0.8, alpha: 1) : .darkGray
        let title = message.kind == .bank ? copy.text("View Bank", "查看 Bank", "查看 Bank") : message.kind == .update ? copy.text("View update", "查看更新", "查看更新") : copy.text("View details", "查看详情", "查看詳情")
        let actionWidth = (card.frame.width - 36) / 2
        let primary = BubbleActionButton(title: title, target: self, action: #selector(viewTapped(_:))); primary.messageID = message.id; primary.token = message.deliveryToken; primary.bezelColor = NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.3, alpha: 1); primary.contentTintColor = .white; primary.bezelStyle = .rounded; primary.frame = CGRect(x: 12, y: 138, width: actionWidth, height: 28); primary.font = .systemFont(ofSize: 12, weight: .semibold); primary.attributedTitle = NSAttributedString(string: title, attributes: [.font: primary.font!, .foregroundColor: NSColor.white]); primary.identifier = .init("notification.primary"); card.addSubview(primary)
        let acknowledge = BubbleActionButton(title: copy.text("Got it", "知道了", "知道了"), target: self, action: #selector(acknowledgeTapped(_:))); acknowledge.messageID = message.id; acknowledge.token = message.deliveryToken; acknowledge.bezelStyle = .rounded; acknowledge.frame = CGRect(x: card.frame.width - 14 - actionWidth, y: 138, width: actionWidth, height: 28); acknowledge.font = .systemFont(ofSize: 12); acknowledge.identifier = .init("notification.acknowledge"); card.addSubview(acknowledge)
        root.setAccessibilityLabel(message.title + ". " + message.body)
        return root
    }
    func show(message: ExperienceNotification, anchor: CGRect, dark: Bool, language: CodexDisplayLanguage) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return false }
        let work = screen.visibleFrame
        let width = min(368, work.width - 16)
        guard width >= 308 else { return false }
        let normalizedAnchor = CGRect(x: anchor.minX, y: -anchor.maxY, width: anchor.width, height: anchor.height)
        let normalizedWork = CGRect(x: work.minX, y: -work.maxY, width: work.width, height: work.height)
        guard let rect = NotificationBubbleLayout.place(anchor: normalizedAnchor, workArea: normalizedWork, size: CGSize(width: width, height: 180)) else { return false }
        panel.contentView = content(message: message, dark: dark, language: language, width: width)
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
