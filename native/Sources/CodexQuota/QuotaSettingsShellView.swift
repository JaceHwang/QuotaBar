import AppKit

@MainActor struct QuotaSettingsPage {
    let title: String
    let symbol: String
    let content: NSView
    var navigationTitle: String? = nil
}

/// Native settings navigation, retaining page controls when changing sections.
@MainActor final class QuotaSettingsShellView: NSView {
    private let pages: [QuotaSettingsPage]
    var pageContents: [NSView] { pages.map(\.content) }
    private let sidebar = NSView()
    private let scroll = NSScrollView()
    private let document = QuotaSettingsDocumentView(frame: .zero)
    private let heading = NSTextField(labelWithString: "")
    private var navigation: [NSButton] = []

    var onCheckUpdates: (() -> Void)?
    private let brand = NSTextField(labelWithString: "QuotaBar")
    private let versionLabel: NSTextField
    var onSelection: ((Int) -> Void)?
    private(set) var selectedPage = 2
    override var isFlipped: Bool { true }
    init(pages: [QuotaSettingsPage], version: String, updateTitle: String = "Check for updates") {
        precondition(pages.count == 4)
        self.pages = pages; versionLabel = NSTextField(labelWithString: "v" + version)
        super.init(frame: NSRect(x: 0, y: 0, width: 1000, height: 680))
        addSubview(sidebar); sidebar.addSubview(brand); sidebar.addSubview(versionLabel)
        let mark = QuotaThemeIconView(frame: NSRect(x: 20, y: 15, width: 38, height: 38)); sidebar.addSubview(mark)
        brand.font = .systemFont(ofSize: 20, weight: .bold); versionLabel.font = .systemFont(ofSize: 11); versionLabel.textColor = .secondaryLabelColor
        for (index, page) in pages.enumerated() {
            let button = NSButton(title: page.navigationTitle ?? page.title, target: self, action: #selector(navigate(_:)))
            button.cell = QuotaSettingsNavigationCell(textCell: page.navigationTitle ?? page.title)
            button.target = self; button.action = #selector(navigate(_:))
            button.toolTip = page.title
            button.tag = index; button.identifier = NSUserInterfaceItemIdentifier("settings.nav.\(index)")
            button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 13, weight: .medium)
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.imageHugsTitle = false; button.wantsLayer = true; button.layer?.cornerRadius = 8
            sidebar.addSubview(button); navigation.append(button)
        }
        heading.font = .systemFont(ofSize: 22, weight: .semibold); addSubview(heading)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = document; addSubview(scroll)
        document.setFrameSize(NSSize(width: 640, height: 600))
        selectPage(2)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func checkUpdates() { selectPage(3); onCheckUpdates?() }
    @objc private func navigate(_ sender: NSButton) { selectPage(sender.tag) }
    func selectPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        selectedPage = index; onSelection?(index); heading.stringValue = pages[index].title
        document.subviews.forEach { $0.removeFromSuperview() }
        let content = pages[index].content; content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: document.leadingAnchor), content.trailingAnchor.constraint(equalTo: document.trailingAnchor), content.topAnchor.constraint(equalTo: document.topAnchor)])
        refreshColors(); needsLayout = true; layoutSubtreeIfNeeded(); scroll.contentView.scroll(to: .zero)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
    private func refreshColors() {
        wantsLayer = true; sidebar.wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            sidebar.layer?.backgroundColor = (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1)).cgColor
            for button in navigation {
                button.layer?.backgroundColor = button.tag == selectedPage ? NSColor.systemGreen.withAlphaComponent(0.15).cgColor : NSColor.clear.cgColor
                button.contentTintColor = .labelColor
            }
        }
    }
    override func layout() {
        super.layout()
        let side: CGFloat = 200
        sidebar.frame = NSRect(x: 0, y: 0, width: side, height: bounds.height)
        // Sidebar is unflipped, so its controls are positioned from the top.
        brand.frame = NSRect(x: 66, y: bounds.height - 54, width: 125, height: 27)
        versionLabel.frame = NSRect(x: 68, y: bounds.height - 73, width: 100, height: 18)
        sidebar.subviews.compactMap { $0 as? QuotaThemeIconView }.first?.frame = NSRect(x: 20, y: bounds.height - 65, width: 36, height: 36)
        for (index, button) in navigation.enumerated() {
            let y = bounds.height - 140 - CGFloat(index) * 40
            button.frame = NSRect(x: 12, y: y, width: side - 24, height: 34)
        }
        let contentWidth = min(640, max(200, bounds.width - side - 48))
        let contentX = side + max(24, (bounds.width - side - contentWidth) / 2)
        heading.frame = NSRect(x: contentX, y: 24, width: contentWidth, height: 32)
        scroll.frame = NSRect(x: contentX, y: 76, width: contentWidth, height: max(0, bounds.height - 96))
        refreshDocumentSize()
    }
    func refreshDocumentSize() {
        let width = max(200, scroll.contentSize.width)
        document.setFrameSize(NSSize(width: width, height: max(scroll.contentSize.height, document.frame.height)))
        document.layoutSubtreeIfNeeded()
        let height = pages[selectedPage].content.fittingSize.height
        document.setFrameSize(NSSize(width: width, height: max(scroll.contentSize.height, ceil(height) + 12)))
    }
}

@MainActor enum QuotaSettingsStyle {
    static func column(_ spacing: CGFloat = 12) -> NSStackView {
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = spacing; return view
    }
    static func label(_ text: String, size: CGFloat = 12, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text); view.font = .systemFont(ofSize: size); view.textColor = secondary ? .secondaryLabelColor : .labelColor; return view
    }
    static func fill(_ child: NSView, in stack: NSStackView) {
        stack.addArrangedSubview(child); child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    static func card(_ content: NSView) -> NSView {
        QuotaSettingsCard(content: content)
    }

    static func line() -> NSView { let box = NSBox(); box.boxType = .separator; return box }
    static func button(_ title: String, target: AnyObject?, action: Selector?, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded; button.controlSize = .regular
        button.font = .systemFont(ofSize: 13)
        if primary { button.bezelColor = .controlAccentColor }
        return button
    }
    static func row(_ title: String, control: NSView, hint: String? = nil) -> NSView {
        let row = NSStackView(); row.spacing = 16; row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        let copy = column(4)
        fill(label(title, size: 13), in: copy)
        if let hint { fill(label(hint, size: 11, secondary: true), in: copy) }
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(copy)
        let spacer = NSView(); spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        row.addArrangedSubview(spacer); row.addArrangedSubview(control)
        control.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setAccessibilityLabel(title)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }
    static func section(_ title: String, content: NSView) -> NSView {
        let group = column(8)
        let heading = label(title, size: 12, secondary: true)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        fill(heading, in: group); fill(card(content), in: group)
        return group
    }
}

/// Use the system switch's keyboard, focus, accessibility and contrast behavior.
@MainActor final class QuotaSettingsSwitch: NSSwitch {}

@MainActor private final class QuotaSettingsNavigationCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 12, y: rect.midY - 9, width: 18, height: 18)
    }
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 38, y: rect.minY, width: max(0, rect.width - 46), height: rect.height)
    }
}

@MainActor private final class QuotaSettingsCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero); wantsLayer = true; layer?.cornerRadius = 10; layer?.borderWidth = 0.5
        addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: topAnchor, constant: 14), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)])
        colors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.borderColor = NSColor.separatorColor.cgColor } }
}
