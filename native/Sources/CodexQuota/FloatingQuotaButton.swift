import AppKit
import QuotaCore

@MainActor
final class FloatingQuotaPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var backgroundTransparency: Double {
        get {
            guard let number = defaults.object(forKey: "standalone.floating.backgroundTransparency") as? NSNumber else { return 20 }
            let value = number.doubleValue
            return value.isFinite ? min(100,max(0,value)) : 20
        }
        set { defaults.set(newValue.isFinite ? min(100,max(0,newValue)) : 20, forKey: "standalone.floating.backgroundTransparency") }
    }
    var enabled: Bool {
        get { defaults.object(forKey: "standalone.floating.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "standalone.floating.enabled") }
    }
    var origin: CGPoint? {
        get {
            guard let values = defaults.array(forKey: "standalone.floating.origin") as? [Double], values.count == 2, values.allSatisfy(\.isFinite) else { return nil }
            return CGPoint(x: values[0], y: values[1])
        }
        set {
            guard let newValue, newValue.x.isFinite, newValue.y.isFinite else { defaults.removeObject(forKey: "standalone.floating.origin"); return }
            defaults.set([Double(newValue.x), Double(newValue.y)], forKey: "standalone.floating.origin")
        }
    }
    func frame(size: CGSize, screens: [CGRect]) -> CGRect {
        let screen = screens.first ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let point = origin ?? CGPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24)
        // Select the closest visible work area, including disconnected-display recovery.
        let selected = screens.min { distance(point, $0) < distance(point, $1) } ?? screen
        let width = min(size.width, selected.width), height = min(size.height, selected.height)
        return CGRect(x: min(max(point.x, selected.minX), selected.maxX - width), y: min(max(point.y, selected.minY), selected.maxY - height), width: width, height: height)
    }
    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

@MainActor
final class FloatingQuotaInteractionView: NSView {
    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var screenPointResolver: ((NSEvent) -> CGPoint)?
    private var origin: CGPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?
    weak var closeControl: NSButton?
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let closeControl, !closeControl.isHidden, closeControl.frame.contains(local) { return closeControl }
        return self
    }
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor: .openHand)
        if let closeControl, !closeControl.isHidden { addCursorRect(closeControl.frame, cursor: .arrow) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func rightMouseDown(with event: NSEvent) { onSecondaryClick?() }
    override func mouseDown(with event: NSEvent) { origin = point(event); dragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let current = point(event), delta = CGPoint(x: current.x - origin.x, y: current.y - origin.y)
        guard dragging || hypot(delta.x, delta.y) >= 4 else { return }
        if !dragging { dragging = true; NSCursor.closedHand.set(); onDragBegan?() }
        onDrag?(delta)
    }
    override func mouseUp(with event: NSEvent) {
        guard origin != nil else { return }
        if dragging { onDragEnded?() } else { onPrimaryClick?() }
        origin = nil; dragging = false; window?.invalidateCursorRects(for: self)
    }
    private func point(_ event: NSEvent) -> CGPoint { screenPointResolver?(event) ?? window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
    override func accessibilityPerformPress() -> Bool { onPrimaryClick?(); return true }
}

@MainActor
final class FloatingQuotaButton: NSObject {
    private final class PassivePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    let preferences: FloatingQuotaPreferences
    private let panel: NSPanel
    let interaction = FloatingQuotaInteractionView(frame: .zero)
    let closeButton = NSButton(frame: .zero)
    var onClose: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let icon = QuotaThemeIconView(frame: .zero)
    private let moodIcon = QuotaMoodView(frame: .zero)
    private let celebration = RecoveryCelebrationController()
    private var experienceDescription = ""
    private var currentMood: QuotaMood = .unavailable
    private(set) var moodEnabled = false
    var isCelebrating: Bool { celebration.active }
    private var dragOrigin: CGPoint?
    var onClick: (() -> Void)?
    var onMenu: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onMove: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragFinished: (() -> Void)?
    var isOnActiveSpace: Bool { panel.isOnActiveSpace }
    private let unreadDot = NSView(frame: CGRect(x: 24, y: 23, width: 5, height: 5))
    var hasUnread = false { didSet { unreadDot.isHidden = !hasUnread } }
    var frame: CGRect? { panel.isVisible ? panel.frame : nil }
    init(preferences: FloatingQuotaPreferences = FloatingQuotaPreferences()) {
        self.preferences = preferences
        panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init()
        panel.contentView = interaction
        interaction.wantsLayer = true; interaction.layer?.cornerRadius = 10
        label.maximumNumberOfLines = 2; label.usesSingleLineMode = false; label.lineBreakMode = .byClipping
        interaction.addSubview(icon); interaction.addSubview(moodIcon); interaction.addSubview(label)
        moodIcon.isHidden = true
        celebration.onChange = { [weak self] active, phase in
            guard let self else { return }; moodIcon.stars = active; moodIcon.sparklePhase = phase
            moodIcon.mood = active && moodEnabled ? .recovered : currentMood
            moodIcon.isHidden = !moodEnabled && !active
        }
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close floating button")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setAccessibilityLabel("Close floating button")
        closeButton.toolTip = "Close floating button"
        closeButton.target = self; closeButton.action = #selector(closeFloatingButton)
        closeButton.isHidden = true
        interaction.addSubview(closeButton); interaction.closeControl = closeButton
        unreadDot.wantsLayer = true; unreadDot.layer?.cornerRadius = 2.5; unreadDot.layer?.backgroundColor = NSColor.systemOrange.cgColor; unreadDot.isHidden = true; interaction.addSubview(unreadDot)
        interaction.setAccessibilityElement(true); interaction.setAccessibilityRole(.button)
        interaction.onPrimaryClick = { [weak self] in self?.onClick?() }
        interaction.onSecondaryClick = { [weak self] in self?.onMenu?() }
        interaction.onHover = { [weak self] value in
            guard let self else { return }
            closeButton.isHidden = !value
            panel.invalidateCursorRects(for: interaction)
            onHover?(value)
        }
        interaction.onDragBegan = { [weak self] in self?.onDragStarted?(); self?.celebration.cancel(); self?.dragOrigin = self?.panel.frame.origin }
        interaction.onDrag = { [weak self] delta in
            guard let self, let dragOrigin else { return }
            preferences.origin = CGPoint(x: dragOrigin.x + delta.x, y: dragOrigin.y + delta.y)
            let frame = preferences.frame(size: panel.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
            panel.setFrame(frame, display: true); onMove?()
        }
        interaction.onDragEnded = { [weak self] in
            guard let self else { return }
            preferences.origin = panel.frame.origin; dragOrigin = nil; onDragFinished?()
        }
    }
    func show(summary: ResetIndicatorSummary?, theme: CodexInterfaceTheme, tooltip: String, fallback: String, dimmed: Bool) {
        guard preferences.enabled else { hide(); return }
        panel.appearance = theme.appKitAppearance; icon.updateAppearance(theme.appKitAppearance)
        let dark = panel.effectiveAppearance.bestMatch(from: [.aqua,.darkAqua]) == .darkAqua
        interaction.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(1-preferences.backgroundTransparency/100).cgColor
        label.attributedStringValue = summary.map { FloatingQuotaTypography.string(summary: $0, alignment: .left) } ?? NSAttributedString(string: fallback, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor])
        // NSTextFieldCell includes the drawing insets omitted by attributed-string size().
        // Measure the same cell that renders the text, and always reserve the close slot.
        let textWidth = ceil(label.cell?.cellSize.width ?? label.intrinsicContentSize.width)
        let width = max(188, textWidth + 67)
        let frame = preferences.frame(size: CGSize(width: width, height: 30), screens: NSScreen.screens.map(\.visibleFrame))
        panel.setFrame(frame, display: true); interaction.frame = CGRect(origin: .zero, size: frame.size)
        icon.frame = CGRect(x: 6, y: 5, width: 20, height: 20)
        moodIcon.frame = CGRect(x: 3, y: 1, width: 28, height: 28); moodIcon.dark = theme == .dark
        let height = min(label.intrinsicContentSize.height, 30)
        label.frame = CGRect(x: 35, y: floor((30 - height) / 2), width: max(0, frame.width - 67), height: height)
        closeButton.frame = CGRect(x: frame.width - 24, y: 5, width: 20, height: 20)
        panel.alphaValue = dimmed ? 0.52 : 1
        interaction.toolTip = tooltip + (moodEnabled ? "\n" + experienceDescription : ""); interaction.setAccessibilityLabel(label.stringValue + (moodEnabled ? "\n" + experienceDescription : ""))
        panel.orderFrontRegardless()
    }
    @objc private func closeFloatingButton() {
        preferences.enabled = false
        hide()
        onClose?()
    }
    func setExperience(mood: QuotaMood, enabled: Bool, description: String = "") {
        experienceDescription = description; currentMood = mood; moodEnabled = enabled; moodIcon.showsCharacter = enabled
        icon.isHidden = enabled; moodIcon.isHidden = !enabled && !celebration.active
        if mood == .unavailable { celebration.cancel() }
        moodIcon.mood = celebration.active && enabled ? .recovered : mood
    }
    func celebrate() { celebration.play(visible: panel.isVisible) }
    func cancelCelebration() { celebration.cancel() }
    func hide() { celebration.cancel(); closeButton.isHidden = true; panel.orderOut(nil) }
    func showMenu(_ menu: NSMenu) { guard let event = NSApp.currentEvent else { return }; NSMenu.popUpContextMenu(menu, with: event, for: interaction) }
}

@MainActor
enum FloatingQuotaTypography {
    private static let labelColumnWidth: CGFloat = 46
    private static let percentColumnWidth: CGFloat = 78

    static func string(
        summary: ResetIndicatorSummary,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let lines = [
            formattedLine(
                summary.primary,
                remainingPercent: summary.primaryRemainingPercent
            ),
            summary.secondary.flatMap { secondary in
                guard let percent = summary.secondaryRemainingPercent else {
                    return nil
                }
                return formattedLine(secondary, remainingPercent: percent)
            }
        ].compactMap { $0 }
        let label = lines.joined(separator: "\n")
        let result = NSMutableAttributedString(string: label)
        let fullRange = NSRange(location: 0, length: result.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        paragraph.lineSpacing = 0
        paragraph.tabStops = [
            NSTextTab(
                textAlignment: .left,
                location: labelColumnWidth,
                options: [:]
            ),
            NSTextTab(
                textAlignment: .left,
                location: percentColumnWidth,
                options: [:]
            )
        ]
        result.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ],
            range: fullRange
        )

        applyPercentStyle(
            to: result,
            label: label,
            remainingPercent: summary.primaryRemainingPercent,
            searchStart: label.startIndex
        )
        if summary.secondary != nil,
           let secondaryPercent = summary.secondaryRemainingPercent,
           let newline = label.firstIndex(of: "\n")
        {
            applyPercentStyle(
                to: result,
                label: label,
                remainingPercent: secondaryPercent,
                searchStart: label.index(after: newline)
            )
        }
        return result
    }

    private static func formattedLine(
        _ line: String,
        remainingPercent: Int
    ) -> String {
        let percent = "\(remainingPercent)%"
        guard let percentRange = line.range(of: percent) else {
            return line
        }
        let window = line[..<percentRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let date = line[percentRange.upperBound...]
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "·")
                )
            )
        return "\(window)\t\(percent)\t· \(date)"
    }

    private static func applyPercentStyle(
        to result: NSMutableAttributedString,
        label: String,
        remainingPercent: Int,
        searchStart: String.Index
    ) {
        let target = "\(remainingPercent)%"
        var searchRange = NSRange(
            searchStart..<label.endIndex,
            in: label
        )
        while searchRange.location != NSNotFound,
              searchRange.location < result.length,
              let range = label.range(
                  of: target,
                  options: [],
                  range: Range(searchRange, in: label)
              )
        {
            let nsRange = NSRange(range, in: label)
            result.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: QuotaColorScale.components(
                        remainingPercent: remainingPercent
                    ).appKitColor
                ],
                range: nsRange
            )
            let nextLocation = nsRange.location + nsRange.length
            searchRange = NSRange(
                location: nextLocation,
                length: max(0, result.length - nextLocation)
            )
        }
    }

}

