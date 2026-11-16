import AppKit

@MainActor enum SettingsLinks {
    static let github = URL(string: "https://github.com/JaceHwang/QuotaBar")!
    static let feedback = URL(string: "https://github.com/JaceHwang/QuotaBar/issues")!
    static let barkDownload = URL(string: "https://apps.apple.com/app/bark-custom-notifications/id1403753865")!
    static let barkTutorial = URL(string: "https://bark.day.app/#/tutorial")!
}

@MainActor final class SettingsLinkButton: SettingsAccentButton {
    private let destination: URL?
    private let opener: (URL) -> Void
    init(_ title: String, destination: URL?, open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.destination = destination; opener = open
        super.init(frame: .zero)
        self.title = title; usesAccentFill = false; variant = .text; target = self; action = #selector(follow)
        bezelStyle = .rounded; isBordered = false; alignment = .left
        font = .systemFont(ofSize: 13); isEnabled = destination != nil
        contentTintColor = destination == nil ? .tertiaryLabelColor : .labelColor
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func follow() { if let destination, isEnabled { opener(destination) } }
}

@MainActor final class AboutSettingsView: NSView {
    init(version: String, updates: NSView?, text: @escaping (String, String, String) -> String) {
        super.init(frame: .zero)
        let stack = QuotaSettingsStyle.column(14); stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        let brand = NSStackView(); brand.spacing = 20; brand.alignment = .centerY
        let character = QuotaThemeIconView(frame: .zero)
        character.widthAnchor.constraint(equalToConstant: 76).isActive = true; character.heightAnchor.constraint(equalToConstant: 76).isActive = true
        character.setAccessibilityLabel("QuotaBar")
        brand.addArrangedSubview(character)
        let words = QuotaSettingsStyle.column(8)
        let name = QuotaSettingsStyle.label("QuotaBar  " + version, size: 19); name.font = .systemFont(ofSize: 19, weight: .semibold)
        words.addArrangedSubview(name); words.addArrangedSubview(QuotaSettingsStyle.label(text("Quota status, at a glance.", "额度状态，一眼即知。", "額度狀態，一眼即知。"), size: 13, secondary: true))
        brand.addArrangedSubview(words); QuotaSettingsStyle.fill(QuotaSettingsStyle.card(brand), in: stack)
        if let updates { QuotaSettingsStyle.fill(updates, in: stack) }
        let links = QuotaSettingsStyle.column(2)
        let heading = QuotaSettingsStyle.label(text("Related links", "相关链接", "相關連結"), size: 13); heading.font = .systemFont(ofSize: 13, weight: .semibold)
        QuotaSettingsStyle.fill(heading, in: links)
        func link(_ title: String, detail: String, symbol: String, url: URL?, id: String) {
            if links.arrangedSubviews.count > 1 { QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: links) }
            let button = SettingsLinkButton(title + (url == nil ? "" : "  ↗"), destination: url); button.identifier = .init(id)
            button.toolTip = url?.absoluteString ?? text("Coming soon", "待上线", "待上線")
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            // The link owns the full label area; a separate secondary line retains readable URLs.
            let block = QuotaSettingsStyle.column(2); block.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0); block.addArrangedSubview(button)
            QuotaSettingsStyle.fill(QuotaSettingsStyle.label(detail, size: 11, secondary: true), in: block)
            QuotaSettingsStyle.fill(block, in: links)
        }
        link("GitHub", detail: "github.com/JaceHwang/QuotaBar", symbol: "chevron.left.forwardslash.chevron.right", url: SettingsLinks.github, id: "about.github")
        link(text("Feedback", "问题反馈", "問題回饋"), detail: text("Share an issue or suggestion", "欢迎提出问题或建议", "歡迎提出問題或建議"), symbol: "bubble.left", url: SettingsLinks.feedback, id: "about.feedback")
        link(text("Official website", "官方网站", "官方網站"), detail: text("Coming soon", "待上线", "待上線"), symbol: "globe", url: nil, id: "about.website")
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(links), in: stack)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Runs independently · Account and settings stored locally", "独立运行 · 账户与设置保存在本机", "獨立執行 · 帳號與設定儲存在本機"), size: 11, secondary: true), in: stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// An offline, illustrative phone + URL diagram, never an official Bark screenshot.
@MainActor final class BarkGuideDiagram: NSView {
    private let text: (String, String, String) -> String
    override var isFlipped: Bool { true }
    init(text: @escaping (String, String, String) -> String) { self.text = text; super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityLabel(text("Illustration: copy only DEMO_KEY from the Bark test URL.", "操作示意：只复制 Bark 测试链接中的 DEMO_KEY。", "操作示意：只複製 Bark 測試連結中的 DEMO_KEY。")) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bg = dark ? NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1) : NSColor(calibratedRed: 0.95, green: 0.96, blue: 1, alpha: 1)
        bg.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let w = bounds.width, phoneWidth = min(128, w * 0.27), x: CGFloat = 18
        let phone = CGRect(x: x, y: 20, width: phoneWidth, height: 132)
        NSColor.labelColor.setFill(); NSBezierPath(roundedRect: phone, xRadius: 20, yRadius: 20).fill()
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: phone.insetBy(dx: 5, dy: 5), xRadius: 15, yRadius: 15).fill()
        func label(_ s: String, _ r: CGRect, size: CGFloat = 11, color: NSColor = .labelColor, bold: Bool = false) {
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
            (s as NSString).draw(in: r, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color, .paragraphStyle: p])
        }
        label(text("Illustration", "操作示意", "操作示意"), CGRect(x: x, y: 2, width: phoneWidth, height: 16), color: .secondaryLabelColor)
        label("Bark", CGRect(x: x + 15, y: 41, width: phoneWidth - 28, height: 18), size: 13, bold: true)
        NSColor.systemPink.setFill(); NSBezierPath(roundedRect: CGRect(x: x + 12, y: 65, width: 16, height: 16), xRadius: 4, yRadius: 4).fill()
        label("B", CGRect(x: x + 17, y: 67, width: 10, height: 13), size: 9, color: .white, bold: true)
        NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: CGRect(x: x + 11, y: 115, width: phoneWidth - 22, height: 22), xRadius: 5, yRadius: 5).fill()
        label("TEST", CGRect(x: x + 23, y: 120, width: phoneWidth - 35, height: 14), size: 9, color: .white, bold: true)
        label(text("Test notification", "测试推送", "測試推播"), CGRect(x: x + 12, y: 87, width: phoneWidth - 22, height: 24), size: 11)
        let right = x + phoneWidth + 20, available = w - right - 14
        let field = CGRect(x: right, y: 48, width: available, height: 39)
        NSColor.systemPurple.withAlphaComponent(dark ? 0.18 : 0.08).setFill(); NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
        let prefixWidth = ("https://api.day.app/" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        label("https://api.day.app/", CGRect(x: right + 10, y: 59, width: prefixWidth + 1, height: 16), size: 11, color: .secondaryLabelColor)
        let keyRect = CGRect(x: right + 10 + prefixWidth, y: 55, width: 73, height: 22)
        NSColor.systemPink.withAlphaComponent(0.15).setFill(); NSBezierPath(roundedRect: keyRect, xRadius: 3, yRadius: 3).fill()
        label("DEMO_KEY", keyRect.insetBy(dx: 3, dy: 3), size: 11, color: .systemPink, bold: true)
        label("/test", CGRect(x: keyRect.maxX + 1, y: 59, width: 29, height: 18), color: .secondaryLabelColor)
        label(text("↑ Copy only this part", "↑ 只复制这一段", "↑ 只複製這一段"), CGRect(x: keyRect.minX + 12, y: 101, width: max(0, w - keyRect.minX - 24), height: 24), size: 12, color: .systemPink)
        label(text("Example URL; your Key will be different.", "示例链接，实际 Key 与此不同。", "範例連結，實際 Key 與此不同。"), CGRect(x: right + 12, y: 128, width: available - 16, height: 32), color: .secondaryLabelColor)
    }
}

@MainActor class SettingsAccentButton: NSButton {
    enum Variant { case primary, secondary, tertiary, ghost, text }
    enum Size { case compact, navigation, md, lg
        var unit: CGFloat { switch self { case .compact: 0.8; case .navigation: 0.9; case .md: 1; case .lg: 16.0 / 14.0 } }
    }
    // Existing callers retain their original API; an explicit variant can refine it.
    var usesAccentFill = true { didSet { needsDisplay = true } }
    var usesBorderlessStyle = false { didSet { needsDisplay = true } }
    var fillColor = NSColor(srgbRed: 0, green: 101.0 / 255, blue: 216.0 / 255, alpha: 1)
    var variant: Variant? { didSet { needsDisplay = true } }
    var buttonSize: Size = .md { didSet { heightConstraint?.constant = 40 * buttonSize.unit; invalidateIntrinsicContentSize(); needsDisplay = true } }
    var usesAutomaticHeight = true { didSet { heightConstraint?.isActive = usesAutomaticHeight } }
    private var heightConstraint: NSLayoutConstraint?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private struct Motion {
        var from: CGFloat = 0
        var target: CGFloat = 0
        var began: TimeInterval = 0
        func value(now: TimeInterval, duration: TimeInterval) -> CGFloat {
            let progress = CGFloat(min(1, max(0, (now - began) / duration)))
            return from + (target - from) * progress
        }
    }
    private var hoverMotion = Motion(), pressMotion = Motion()
    private var animationTimer: Timer?
    @objc private func animationTick(_ timer: Timer) {
        needsDisplay = true
        let now = ProcessInfo.processInfo.systemUptime
        if now - max(hoverMotion.began, pressMotion.began) >= 0.16 { timer.invalidate(); animationTimer = nil }
    }
    private func updateMotion(_ motion: inout Motion, target: CGFloat, now: TimeInterval) -> Bool {
        guard motion.target != target else { return false }
        motion.from = motion.value(now: now, duration: 0.16); motion.target = target; motion.began = now
        return true
    }
    private var effectiveVariant: Variant { variant ?? (usesAccentFill ? .primary : (usesBorderlessStyle ? .ghost : .secondary)) }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        font = .systemFont(ofSize: 14, weight: .semibold)
        isBordered = false
        let height = heightAnchor.constraint(equalToConstant: 40); height.isActive = true; heightConstraint = height
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var intrinsicContentSize: NSSize {
        let u = buttonSize.unit
        if title.isEmpty { return NSSize(width: 40 * u, height: 40 * u) }
        let renderedTitle = effectiveVariant == .text && !title.hasSuffix("↗") ? title + "  →" : title
        let width = NSAttributedString(string: renderedTitle, attributes: [.font: NSFont.systemFont(ofSize: 14 * u, weight: .semibold)]).size().width
        return NSSize(width: max((buttonSize == .compact ? 40 : 100) * u, ceil(width) + 36 * u + (image == nil ? 0 : 22 * u)), height: 40 * u)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let u = buttonSize.unit, kind = effectiveVariant, pressed = isEnabled && isHighlighted
        let now = ProcessInfo.processInfo.systemUptime
        let changedHover = updateMotion(&hoverMotion, target: hovering && isEnabled ? 1 : 0, now: now)
        let changedPress = updateMotion(&pressMotion, target: pressed ? 1 : 0, now: now)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if (changedHover || changedPress) && !reduceMotion && animationTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(animationTick(_:)), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common); animationTimer = timer
        }
        let hoverColor = reduceMotion ? hoverMotion.target : hoverMotion.value(now: now, duration: 0.16)
        let hoverShadow = reduceMotion ? hoverMotion.target : hoverMotion.value(now: now, duration: 0.14)
        let pressColor = reduceMotion ? pressMotion.target : pressMotion.value(now: now, duration: 0.16)
        let pressShadow = reduceMotion ? pressMotion.target : pressMotion.value(now: now, duration: 0.14)
        let pressMove = reduceMotion ? pressMotion.target : pressMotion.value(now: now, duration: 0.12)
        func color(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
        }
        let dark = kind == .primary
        let darkAppearance = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let adaptiveDark = darkAppearance && (kind == .secondary || kind == .tertiary)
        let darkFace = dark || adaptiveDark
        var top: NSColor = color(dark ? 0x404859 : adaptiveDark ? (kind == .tertiary ? 0x3B3B3B : 0x4A4A4A) : kind == .tertiary ? 0xF3F4F6 : 0xFFFFFF)
        var bottom: NSColor = color(dark ? 0x273042 : adaptiveDark ? (kind == .tertiary ? 0x2C2C2C : 0x353535) : kind == .tertiary ? 0xE7E9EC : 0xF4F5F7)
        top = top.blended(withFraction: 0.08 * hoverColor, of: .white)!
        bottom = bottom.blended(withFraction: 0.08 * hoverColor, of: .white)!
        let originalTop = top, originalBottom = bottom
        top = originalTop.blended(withFraction: pressColor, of: originalBottom)!
        bottom = originalBottom.blended(withFraction: pressColor, of: originalTop)!
        let face = bounds.insetBy(dx: u, dy: 2 * u).offsetBy(dx: 0, dy: -pressMove * u)
        let shape = NSBezierPath(roundedRect: face, xRadius: 10 * u, yRadius: 10 * u)
        let filled = kind == .primary || kind == .secondary || kind == .tertiary
        NSGraphicsContext.saveGraphicsState()
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        if filled {
            // Draw contact and lift separately, with dimensions scaled by the label size.
            for (blur, depth, opacity) in [
                (CGFloat(2) - pressShadow, CGFloat(1), darkFace ? CGFloat(0.18) : CGFloat(0.06)),
                ((CGFloat(10) + 6 * hoverShadow) * (1 - pressShadow) + pressShadow,
                 (CGFloat(4) + 4 * hoverShadow) * (1 - pressShadow) + pressShadow,
                 (darkFace ? CGFloat(0.28) : CGFloat(0.09)) * (1 - pressShadow))] {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
                shadow.shadowBlurRadius = blur * u; shadow.shadowOffset = NSSize(width: 0, height: -depth * u); shadow.set()
                bottom.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
            }
            NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: 90)
            (dark ? color(0x12161F) : adaptiveDark ? color(0x202020) : NSColor.black.withAlphaComponent(kind == .secondary ? 0.14 : 0.1)).setStroke()
            shape.lineWidth = u; shape.stroke()
            NSGraphicsContext.saveGraphicsState(); shape.addClip()
            let highlight = NSBezierPath(); highlight.move(to: NSPoint(x: face.minX + u, y: face.maxY - u)); highlight.line(to: NSPoint(x: face.maxX - u, y: face.maxY - u)); highlight.lineWidth = u
            NSColor.white.withAlphaComponent((darkFace ? 0.18 : 0.9) * (1 - pressShadow)).setStroke(); highlight.stroke()
            if pressShadow > 0 {
                NSGraphicsContext.saveGraphicsState()
                let inner = NSShadow(); inner.shadowColor = NSColor.black.withAlphaComponent((darkFace ? 0.4 : 0.14) * pressShadow)
                inner.shadowBlurRadius = 2 * u; inner.shadowOffset = NSSize(width: 0, height: -u); inner.set()
                NSColor.black.setFill(); NSRect(x: face.minX, y: face.maxY, width: face.width, height: 3 * u).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let shade = NSBezierPath(); shade.move(to: NSPoint(x: face.minX + u, y: face.minY + u)); shade.line(to: NSPoint(x: face.maxX - u, y: face.minY + u)); shade.lineWidth = u
            NSColor.black.withAlphaComponent(darkFace ? 0.22 : 0.06).setStroke(); shade.stroke(); NSGraphicsContext.restoreGraphicsState()
            if !darkFace && pressShadow > 0 {
                let line = NSBezierPath(); line.move(to: NSPoint(x: face.minX + 3 * u, y: face.minY - u)); line.line(to: NSPoint(x: face.maxX - 3 * u, y: face.minY - u)); line.lineWidth = u
                NSColor.white.withAlphaComponent(0.9 * pressShadow).setStroke(); line.stroke()
            }
        } else if kind == .ghost && isEnabled {
            NSColor.labelColor.withAlphaComponent(0.06 * hoverColor + 0.07 * pressColor).setFill(); shape.fill()
            if pressShadow > 0 {
                NSGraphicsContext.saveGraphicsState(); shape.addClip()
                let inset = NSShadow(); inset.shadowColor = NSColor.black.withAlphaComponent(0.14 * pressShadow)
                inset.shadowBlurRadius = 2 * u; inset.shadowOffset = NSSize(width: 0, height: -u); inset.set()
                NSColor.black.setFill(); NSRect(x: face.minX, y: face.maxY, width: face.width, height: 3 * u).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // Dim the material independently; applying the same opacity again to the
        // system's already-dimmed text makes disabled links illegible in dark mode.
        NSGraphicsContext.restoreGraphicsState()
        let foreground: NSColor
        if isEnabled { foreground = darkFace ? .white : filled ? color(0x303640) : .labelColor }
        else { foreground = darkFace ? NSColor.white.withAlphaComponent(0.65) : filled ? color(0x303640, alpha: 0.65) : .secondaryLabelColor }
        let font = NSFont.systemFont(ofSize: 14 * u, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        if kind == .text { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if dark { let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowOffset = NSSize(width: 0, height: -u); attributes[.shadow] = shadow }
        let hasLinkArrow = kind == .text && !title.isEmpty
        let labelText = hasLinkArrow && title.hasSuffix("↗") ? String(title.dropLast()).trimmingCharacters(in: .whitespaces) : title
        let label = NSAttributedString(string: labelText, attributes: attributes)
        var arrowAttributes = attributes; arrowAttributes.removeValue(forKey: .underlineStyle)
        let arrow = NSAttributedString(string: title.hasSuffix("↗") ? "↗" : "→", attributes: arrowAttributes)
        let arrowWidth: CGFloat = hasLinkArrow ? arrow.size().width + 6 * u : 0
        let size = label.size(), iconWidth: CGFloat = image == nil ? 0 : (title.isEmpty ? 16 * u : 22 * u)
        let start = alignment == .left ? 12 * u : (bounds.width - size.width - iconWidth - arrowWidth) / 2, offset = -pressMove * u
        if let image {
            let icon = image.copy() as! NSImage; icon.size = NSSize(width: 16 * u, height: 16 * u)
            let rect = NSRect(x: start, y: (bounds.height - 16 * u) / 2 + offset, width: 16 * u, height: 16 * u)
            let tinted = NSImage(size: rect.size, flipped: false) { area in icon.draw(in: area); foreground.setFill(); area.fill(using: .sourceIn); return true }; tinted.draw(in: rect)
        }
        label.draw(at: CGPoint(x: start + iconWidth, y: (bounds.height - size.height) / 2 + offset))
        if hasLinkArrow { arrow.draw(at: CGPoint(x: start + iconWidth + size.width + 6 * u + 2 * u * hoverColor, y: (bounds.height - arrow.size().height) / 2 + offset)) }
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2 * u, dy: 2 * u), xRadius: 8 * u, yRadius: 8 * u); ring.lineWidth = 2 * u; ring.stroke() }
    }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
}

@MainActor final class AboutBatteryArtwork: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.scaleBy(x: bounds.width / 84, y: bounds.height / 84)
        let ink = NSColor(calibratedRed: 0.13, green: 0.26, blue: 0.22, alpha: 1)
        func rect(_ r: CGRect, radius: CGFloat, fill: NSColor, stroke: Bool = false) { let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius); fill.setFill(); p.fill(); if stroke { ink.setStroke(); p.lineWidth = 2.4; p.stroke() } }
        rect(CGRect(x: 0, y: 0, width: 84, height: 84), radius: 22, fill: NSColor(calibratedRed: 0.81, green: 0.99, blue: 0.9, alpha: 1))
        rect(CGRect(x: 36, y: 10, width: 12, height: 9), radius: 3, fill: .white, stroke: true)
        let arms = NSBezierPath(); arms.move(to: CGPoint(x: 20, y: 51)); arms.line(to: CGPoint(x: 14, y: 57)); arms.move(to: CGPoint(x: 61, y: 43)); arms.line(to: CGPoint(x: 69, y: 36)); arms.move(to: CGPoint(x: 29, y: 70)); arms.line(to: CGPoint(x: 27, y: 76)); arms.move(to: CGPoint(x: 50, y: 70)); arms.line(to: CGPoint(x: 53, y: 76)); ink.setStroke(); arms.lineWidth = 2.4; arms.stroke()
        rect(CGRect(x: 21, y: 18, width: 40, height: 52), radius: 8, fill: .white, stroke: true)
        rect(CGRect(x: 25, y: 23, width: 32, height: 42), radius: 5, fill: NSColor(calibratedRed: 0.53, green: 0.91, blue: 0.72, alpha: 1))
        ink.setFill(); for x: CGFloat in [34, 49] { NSBezierPath(ovalIn: CGRect(x: x - 1.8, y: 41, width: 3.6, height: 4.2)).fill() }
        let smile = NSBezierPath(); smile.move(to: CGPoint(x: 37, y: 49)); smile.curve(to: CGPoint(x: 47, y: 49), controlPoint1: CGPoint(x: 40, y: 55), controlPoint2: CGPoint(x: 44, y: 55)); smile.lineWidth = 2; ink.setStroke(); smile.stroke()
    }
}

@MainActor final class BarkGuideStepStrip: NSView {
    private let labels: [String]
    override var isFlipped: Bool { true }
    init(text: (String, String, String) -> String) {
        labels = [text("Install Bark", "安装 Bark", "安裝 Bark"), text("Get Key", "获取 Key", "取得 Key"), text("Connect & test", "连接测试", "連線測試")]
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityLabel(labels.joined(separator: ", "))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let step = bounds.width / 3
        let green = NSColor(srgbRed: 8.0 / 255, green: 127.0 / 255, blue: 91.0 / 255, alpha: 1)
        for (index, label) in labels.enumerated() {
            let x = CGFloat(index) * step + 4
            (index < 2 ? green : NSColor.quaternaryLabelColor).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: 4, width: 24, height: 24)).fill()
            let number = NSAttributedString(string: String(index + 1), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: index < 2 ? NSColor.white : NSColor.secondaryLabelColor])
            number.draw(at: CGPoint(x: x + (24 - number.size().width) / 2, y: 8))
            let name = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
            name.draw(in: CGRect(x: x + 32, y: 9, width: step - 38, height: 17))
            if index < 2 {
                let start = x + 32 + name.size().width + 8, end = x + step - 7
                if end > start { NSColor.separatorColor.setStroke(); let line = NSBezierPath(); line.move(to: CGPoint(x: start, y: 16)); line.line(to: CGPoint(x: end, y: 16)); line.lineWidth = 1; line.stroke() }
            }
        }
    }
}
