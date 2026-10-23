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
        self.title = title; usesAccentFill = false; target = self; action = #selector(follow)
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
        let character = AboutBatteryArtwork()
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
            let block = QuotaSettingsStyle.column(2); block.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0); QuotaSettingsStyle.fill(button, in: block)
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
        label(text("↑ Copy only this part", "↑ 只复制这一段", "↑ 只複製這一段"), CGRect(x: right + 12, y: 101, width: available - 16, height: 24), size: 12, color: .systemPink)
        label(text("Example URL; your Key will be different.", "示例链接，实际 Key 与此不同。", "範例連結，實際 Key 與此不同。"), CGRect(x: right + 12, y: 128, width: available - 16, height: 32), color: .secondaryLabelColor)
    }
}

@MainActor class SettingsAccentButton: NSButton {
    var usesAccentFill = true
    var fillColor = NSColor(srgbRed: 8.0 / 255, green: 127.0 / 255, blue: 91.0 / 255, alpha: 1)
    override func draw(_ dirtyRect: NSRect) {
        guard usesAccentFill else { super.draw(dirtyRect); return }
        let bg = isEnabled ? (isHighlighted ? fillColor.blended(withFraction: 0.15, of: .black)! : fillColor) : fillColor.withAlphaComponent(0.4)
        bg.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let label = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
        let size = label.size(); label.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6); ring.lineWidth = 2; ring.stroke() }
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
