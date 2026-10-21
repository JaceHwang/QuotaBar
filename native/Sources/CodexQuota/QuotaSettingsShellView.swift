import AppKit

@MainActor struct QuotaSettingsPage {
    let title: String
    let symbol: String
    let content: NSView
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
    private let updateShortcut = NSButton()
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
            let button = NSButton(title: page.title, target: self, action: #selector(navigate(_:)))
            button.tag = index; button.identifier = NSUserInterfaceItemIdentifier("settings.nav.\(index)")
            button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 13, weight: .medium)
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.imageHugsTitle = false; button.wantsLayer = true; button.layer?.cornerRadius = 8
            sidebar.addSubview(button); navigation.append(button)
        }
        heading.font = .systemFont(ofSize: 22, weight: .bold); addSubview(heading)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = document; addSubview(scroll)
        updateShortcut.title = updateTitle + "  ›"; updateShortcut.target = self; updateShortcut.action = #selector(checkUpdates)
        updateShortcut.isBordered = false; updateShortcut.alignment = .left; updateShortcut.font = .systemFont(ofSize: 12)
        sidebar.addSubview(updateShortcut)
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
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            sidebar.layer?.backgroundColor = (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1)).cgColor
            for button in navigation {
                button.layer?.backgroundColor = button.tag == selectedPage ? NSColor.systemGreen.withAlphaComponent(0.15).cgColor : NSColor.clear.cgColor
                button.contentTintColor = button.tag == selectedPage ? .labelColor : .secondaryLabelColor
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
            let y = bounds.height - 140 - CGFloat(index) * 48
            button.frame = NSRect(x: 12, y: y, width: side - 24, height: 40)
        }
        updateShortcut.frame = NSRect(x: 18, y: 20, width: side - 30, height: 32)
        heading.frame = NSRect(x: side + 24, y: 26, width: max(0, bounds.width - side - 48), height: 32)
        scroll.frame = NSRect(x: side + 24, y: 78, width: max(0, bounds.width - side - 48), height: max(0, bounds.height - 98))
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
    static func row(_ title: String, control: NSView) -> NSView {
        let row = NSStackView(); row.spacing = 16; row.addArrangedSubview(label(title, size: 13))
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); row.addArrangedSubview(spacer); row.addArrangedSubview(control)
        return row
    }
}

/// Keep native switch keyboard/accessibility behavior with the approved green accent.
@MainActor final class QuotaSettingsSwitch: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); title = ""; isBordered = false; setButtonType(.pushOnPushOff)
        setAccessibilityRole(.checkBox)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 1, y: (bounds.height - 20)/2, width: 36, height: 20)
        (state == .on ? NSColor.systemGreen : NSColor(calibratedWhite: 0.65, alpha: 1)).withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: state == .on ? track.maxX - 18 : track.minX + 2, y: track.minY + 2, width: 16, height: 16)).fill()
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); let focus = NSBezierPath(roundedRect: track.insetBy(dx: -1, dy: -1), xRadius: 11, yRadius: 11); focus.lineWidth = 2; focus.stroke() }
    }
}

@MainActor private final class QuotaSettingsCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero); wantsLayer = true; layer?.cornerRadius = 10; layer?.borderWidth = 1
        addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: topAnchor, constant: 14), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)])
        colors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.borderColor = NSColor.separatorColor.cgColor } }
}
