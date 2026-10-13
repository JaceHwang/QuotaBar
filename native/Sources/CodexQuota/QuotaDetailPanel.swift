import AppKit
import QuotaCore

@MainActor
final class QuotaDetailPanel {
    private final class PassivePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel: NSPanel
    private var lastContent: QuotaDetailContent?
    private var lastIndicatorFrame: CGRect?
    private var lastTheme: CodexInterfaceTheme?
    private var lastIsLockedOpen = false
    private var lastLockAccessibilityLabel = ""
    private var requestedHeight: CGFloat?
    var onOpenURL: ((URL) -> Void)?
    var onSettingsButtonTapped: ((CGRect) -> Void)?
    var onLockOpenToggle: (() -> Void)?

    init() {
        panel = PassivePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    var frame: CGRect? {
        panel.isVisible ? panel.frame : nil
    }

    func show(
        content: QuotaDetailContent,
        relativeTo indicatorFrame: CGRect,
        theme: CodexInterfaceTheme,
        isLockedOpen: Bool = false,
        lockAccessibilityLabel: String = "Keep popover open"
    ) {
        if
            panel.isVisible,
            lastContent == content,
            lastIndicatorFrame == indicatorFrame,
            lastTheme == theme,
            lastIsLockedOpen == isLockedOpen,
            lastLockAccessibilityLabel == lockAccessibilityLabel
        {
            return
        }
        lastContent = content
        lastIndicatorFrame = indicatorFrame
        lastTheme = theme
        lastIsLockedOpen = isLockedOpen
        lastLockAccessibilityLabel = lockAccessibilityLabel

        let screen = NSScreen.screens.first {
            $0.frame.contains(
                CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
            )
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? indicatorFrame.insetBy(
            dx: -400,
            dy: -400
        )
        apply(
            content: content,
            indicatorFrame: indicatorFrame,
            theme: theme,
            isLockedOpen: isLockedOpen,
            lockAccessibilityLabel: lockAccessibilityLabel,
            visibleFrame: visibleFrame
        )
    }

    private func apply(
        content: QuotaDetailContent,
        indicatorFrame: CGRect,
        theme: CodexInterfaceTheme,
        isLockedOpen: Bool,
        lockAccessibilityLabel: String,
        visibleFrame: CGRect
    ) {
        let resolvedLayout = QuotaDetailPanelResolvedLayout.resolve(
            content: content,
            indicatorFrame: indicatorFrame,
            visibleFrame: visibleFrame,
            requestedHeight: requestedHeight
        )
        let rowHeights = resolvedLayout.rowHeights
        let panelFrame = resolvedLayout.frame
        let appearance = theme.appKitAppearance
        panel.appearance = appearance
        var card: QuotaDetailCardView?
        appearance.performAsCurrentDrawingAppearance {
            card = QuotaDetailCardView(
                frame: CGRect(origin: .zero, size: panelFrame.size),
                content: content,
                rowHeights: rowHeights,
                isLockedOpen: isLockedOpen,
                lockAccessibilityLabel: lockAccessibilityLabel,
                onLockOpenToggle: { [weak self] in
                    self?.onLockOpenToggle?()
                },
                onOpenURL: { [weak self] destination in
                    self?.onOpenURL?(destination)
                },
                onSettingsButtonTapped: { [weak self] button in
                    guard let self,
                          let window = button.window
                    else {
                        return
                    }
                    let windowFrame = button.convert(button.bounds, to: nil)
                    self.onSettingsButtonTapped?(
                        window.convertToScreen(windowFrame)
                    )
                },
                onResizeHeight: { [weak self] requestedHeight in
                    self?.resize(to: requestedHeight)
                },
                onResizeEnded: { [weak self] in
                    self?.finishResize()
                }
            )
            card?.appearance = appearance
        }
        if let card {
            Self.install(card, into: panel, frame: panelFrame)
        }
        panel.orderFrontRegardless()
    }

    /// Installs a detail card only after the panel has its final geometry.
    ///
    /// `NSPanel` applies autoresizing masks as soon as a content view is
    /// attached. A cold panel starts at a zero-sized content rect, so attaching
    /// the card first permanently distorts its top-anchored header and
    /// stretchable scroll area on the first render.
    static func install(
        _ card: NSView,
        into panel: NSPanel,
        frame: CGRect
    ) {
        panel.setFrame(frame, display: false)
        panel.contentView = card
        card.frame = CGRect(origin: .zero, size: frame.size)
        card.layoutSubtreeIfNeeded()
    }

    private func resize(to requestedHeight: CGFloat) {
        guard
            let content = lastContent,
            let indicatorFrame = lastIndicatorFrame
        else {
            return
        }
        self.requestedHeight = requestedHeight
        let screen = NSScreen.screens.first {
            $0.frame.contains(
                CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
            )
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? indicatorFrame.insetBy(
            dx: -400,
            dy: -400
        )
        let resolvedLayout = QuotaDetailPanelResolvedLayout.resolve(
            content: content,
            indicatorFrame: indicatorFrame,
            visibleFrame: visibleFrame,
            requestedHeight: requestedHeight
        )
        panel.setFrame(resolvedLayout.frame, display: true)
        panel.contentView?.setFrameSize(resolvedLayout.frame.size)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func finishResize() {
        guard
            let content = lastContent,
            let indicatorFrame = lastIndicatorFrame,
            let theme = lastTheme
        else {
            return
        }
        let screen = NSScreen.screens.first {
            $0.frame.contains(
                CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
            )
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? indicatorFrame.insetBy(
            dx: -400,
            dy: -400
        )
        apply(
            content: content,
            indicatorFrame: indicatorFrame,
            theme: theme,
            isLockedOpen: lastIsLockedOpen,
            lockAccessibilityLabel: lastLockAccessibilityLabel,
            visibleFrame: visibleFrame
        )
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@MainActor
struct QuotaDetailPanelResolvedLayout {
    let frame: CGRect
    let rowHeights: [CGFloat]

    static func resolve(
        content: QuotaDetailContent,
        indicatorFrame: CGRect,
        visibleFrame: CGRect,
        requestedHeight: CGFloat? = nil
    ) -> QuotaDetailPanelResolvedLayout {
        let widthFrame = QuotaDetailLayout.frame(
            indicatorFrame: indicatorFrame,
            rowContentHeight: 0,
            visibleFrame: visibleFrame,
            tokenUsageVisible: content.tokenUsage != nil,
            secondaryQuotaVisible: content.quotaWindows.count > 1,
            requestedHeight: requestedHeight
        )
        let rowHeights = QuotaDetailRowMetrics.heights(
            for: content.rows,
            cardWidth: widthFrame.width,
            remainingPercent: content.remainingPercent
        )
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicatorFrame,
            rowContentHeight: rowHeights.reduce(0, +),
            visibleFrame: visibleFrame,
            tokenUsageVisible: content.tokenUsage != nil,
            secondaryQuotaVisible: content.quotaWindows.count > 1,
            requestedHeight: requestedHeight
        )
        return QuotaDetailPanelResolvedLayout(
            frame: frame,
            rowHeights: rowHeights
        )
    }
}

@MainActor
final class QuotaDetailCardView: NSView {
    init(
        frame frameRect: NSRect,
        content: QuotaDetailContent,
        rowHeights: [CGFloat],
        version: String? = nil,
        isLockedOpen: Bool = false,
        lockAccessibilityLabel: String = "Keep popover open",
        onLockOpenToggle: @escaping () -> Void = {},
        onOpenURL: @escaping (URL) -> Void,
        onSettingsButtonTapped: @escaping (NSButton) -> Void = { _ in },
        onResizeHeight: @escaping (CGFloat) -> Void = { _ in },
        onResizeEnded: @escaping () -> Void = {}
    ) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        let material = QuotaCardMaterialView(frame: bounds)
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        let title = label(
            content.title,
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .labelColor,
            alignment: .left
        )
        title.lineBreakMode = .byTruncatingTail

        let displayedVersion = version ?? (
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "dev"
        )
        let versionBadge = VersionBadgeView(text: "v\(displayedVersion)")
        let lockButton = QuotaDetailLockButton(
            frame: .zero,
            isLockedOpen: isLockedOpen,
            accessibilityLabel: lockAccessibilityLabel,
            onActivate: onLockOpenToggle
        )
        let secondaryQuotaVisible = content.quotaWindows.count > 1

        let remaining = label(
            "\(content.remainingPercent)%",
            font: .systemFont(ofSize: 24, weight: .semibold),
            color: QuotaColorScale.components(
                remainingPercent: content.remainingPercent
            ).appKitColor,
            alignment: .right
        )
        let headerFrames = QuotaDetailLayout.headerFrames(
            in: bounds,
            titleWidth: QuotaDetailLayout.titleWidth(
                intrinsicWidth: title.intrinsicContentSize.width,
                fittingWidth: title.fittingSize.width
            ),
            versionBadgeWidth: versionBadge.intrinsicContentSize.width,
            lockButtonWidth: 28,
            secondaryQuotaVisible: secondaryQuotaVisible
        )
        let themeIcon = QuotaThemeIconView(frame: CGRect(
            x: QuotaDetailLayout.contentHorizontalInset,
            y: bounds.maxY - 50,
            width: 32,
            height: 32
        ))
        themeIcon.autoresizingMask = [.minYMargin]
        title.autoresizingMask = [.minYMargin]
        lockButton.autoresizingMask = [.minYMargin]
        versionBadge.autoresizingMask = [.minYMargin]
        remaining.autoresizingMask = [.minYMargin]
        title.frame = headerFrames.title
        lockButton.frame = headerFrames.lockButton
        versionBadge.frame = headerFrames.versionBadge
        if let primaryWindow = content.quotaWindows.first {
            let primaryWindowLabel = label(
                primaryWindow.label,
                font: .systemFont(ofSize: 14, weight: .medium),
                color: .labelColor,
                alignment: .left
            )
            primaryWindowLabel.frame = headerFrames.primaryLabel
            primaryWindowLabel.autoresizingMask = [.minYMargin]
            addSubview(primaryWindowLabel)
        }
        remaining.frame = headerFrames.remaining
        addSubview(themeIcon)
        addSubview(title)
        addSubview(lockButton)
        addSubview(versionBadge)
        addSubview(remaining)

        let progress = QuotaProgressView(
            frame: headerFrames.progress,
            value: content.remainingPercent
        )
        progress.autoresizingMask = [.minYMargin, .width]
        addSubview(progress)

        if let secondaryWindow = content.quotaWindows.dropFirst().first {
            let secondaryWindowLabel = label(
                secondaryWindow.label,
                font: .systemFont(ofSize: 14, weight: .medium),
                color: .labelColor,
                alignment: .left
            )
            secondaryWindowLabel.frame = headerFrames.secondaryLabel
            secondaryWindowLabel.autoresizingMask = [.minYMargin]
            addSubview(secondaryWindowLabel)

            let secondaryRemaining = label(
                "\(secondaryWindow.remainingPercent)%",
                font: .systemFont(ofSize: 24, weight: .semibold),
                color: QuotaColorScale.components(
                    remainingPercent: secondaryWindow.remainingPercent
                ).appKitColor,
                alignment: .right
            )
            secondaryRemaining.frame = headerFrames.secondaryRemaining
            secondaryRemaining.autoresizingMask = [.minYMargin]
            addSubview(secondaryRemaining)

            let secondaryProgress = QuotaProgressView(
                frame: headerFrames.secondaryProgress,
                value: secondaryWindow.remainingPercent
            )
            secondaryProgress.autoresizingMask = [.minYMargin, .width]
            addSubview(secondaryProgress)
        }

        let informationFrames = QuotaDetailLayout.informationFrames(
            in: bounds,
            tokenUsageVisible: content.tokenUsage != nil,
            secondaryQuotaVisible: secondaryQuotaVisible
        )
        let topDivider = NSBox(
            frame: informationFrames.topDivider
        )
        topDivider.boxType = .separator
        topDivider.autoresizingMask = [.minYMargin, .width]
        addSubview(topDivider)

        if let tokenUsage = content.tokenUsage {
            let tokenUsageView = QuotaTokenUsageView(
                frame: informationFrames.tokenBand,
                presentation: tokenUsage,
                remainingPercent: content.remainingPercent
            )
            tokenUsageView.autoresizingMask = [.minYMargin, .width]
            addSubview(tokenUsageView)
        }

        if content.tokenUsage != nil {
            let tokenDivider = NSBox(frame: informationFrames.tokenDivider)
            tokenDivider.boxType = .separator
            tokenDivider.autoresizingMask = [.minYMargin, .width]
            addSubview(tokenDivider)
        }

        let rowAreaFrame = informationFrames.rowArea
        let scrollView = NSScrollView(frame: rowAreaFrame)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = rowHeights.reduce(0, +) > rowAreaFrame.height
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        let rowContentWidth = scrollView.contentSize.width
        let effectiveRowHeights = scrollView.hasVerticalScroller
            ? QuotaDetailRowMetrics.heights(
                for: content.rows,
                cardWidth: rowContentWidth,
                remainingPercent: content.remainingPercent
            )
            : rowHeights
        let rowDocumentHeight = effectiveRowHeights.reduce(0, +)
        let rowDocument = FlippedView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: rowContentWidth,
                height: max(rowAreaFrame.height, rowDocumentHeight)
            )
        )

        var rowY: CGFloat = 0
        for (index, row) in content.rows.enumerated() {
            let rowHeight = effectiveRowHeights[index]
            let isStacked = rowHeight > QuotaDetailLayout.rowHeight
            let icon = QuotaDetailIconView(
                kind: QuotaDetailIconKind.kind(
                    forRowLabel: row.label,
                    index: index,
                    count: content.rows.count
                )
            )
            icon.frame = CGRect(
                x: QuotaDetailLayout.contentHorizontalInset,
                y: rowY + (isStacked ? (rowHeight - 18) / 2 : 5),
                width: 18,
                height: 18
            )
            rowDocument.addSubview(icon)
            let rowLabel = label(
                row.label,
                font: QuotaDetailRowMetrics.labelFont,
                color: .labelColor,
                alignment: .left
            )
            let labelWidth = min(
                118,
                ceil(rowLabel.intrinsicContentSize.width + 2)
            )
            rowLabel.frame = CGRect(
                x: 42,
                y: rowY + (isStacked ? (rowHeight - 16) / 2 : 7),
                width: labelWidth,
                height: 16
            )
            rowDocument.addSubview(rowLabel)

            let value = label(
                row.value,
                font: QuotaDetailRowMetrics.valueFont,
                color: .labelColor,
                alignment: .right
            )
            value.attributedStringValue = QuotaDetailValueTypography.string(
                for: row,
                remainingPercent: row.accentRemainingPercent ?? content.remainingPercent
            )
            if isStacked {
                let valueHeight = rowHeight - 8
                value.maximumNumberOfLines = 2
                value.lineBreakMode = .byCharWrapping
                value.frame = CGRect(
                    x: 42,
                    y: rowY + 4,
                    width: rowContentWidth - 52,
                    height: valueHeight
                )
            } else {
                value.lineBreakMode = .byTruncatingTail
                let valueX = max(148, rowLabel.frame.maxX + 10)
                value.frame = CGRect(
                    x: valueX,
                    y: rowY + 7,
                    width: rowContentWidth - valueX - 12,
                    height: 16
                )
            }
            rowDocument.addSubview(value)
            if index < content.rows.indices.last! {
                let separator = NSBox(
                    frame: CGRect(
                        x: 42,
                        y: rowY + rowHeight - 1,
                        width: max(0, rowContentWidth - 54),
                        height: 1
                    )
                )
                separator.boxType = .separator
                rowDocument.addSubview(separator)
            }
            rowY += rowHeight
        }

        scrollView.documentView = rowDocument
        addSubview(scrollView)

        let footerDivider = NSBox(frame: informationFrames.footerDivider)
        footerDivider.boxType = .separator
        addSubview(footerDivider)
        addSubview(
            QuotaFooterView(
                frame: informationFrames.footer,
                name: content.footerName,
                avatarSeed: content.footerName,
                avatarURL: content.footerAvatarURL,
                informationEntry: content.informationEntry,
                onOpenURL: onOpenURL,
                onSettingsButtonTapped: onSettingsButtonTapped
            )
        )
        let resizeHint = QuotaResizeHintView(text: content.resizeHint)
        let resizeHintSize = resizeHint.intrinsicContentSize
        resizeHint.frame = CGRect(
            x: informationFrames.footer.midX - resizeHintSize.width / 2,
            y: informationFrames.footer.maxY + 4,
            width: resizeHintSize.width,
            height: resizeHintSize.height
        )
        resizeHint.isHidden = true
        addSubview(resizeHint)

        let resizeHandle = QuotaDetailHeightResizeHandleView(
            frame: CGRect(
                x: informationFrames.footer.midX - 22,
                y: informationFrames.footer.maxY - 7,
                width: 44,
                height: 14
            ),
            accessibilityLabel: content.resizeHint,
            onResizeHeight: onResizeHeight,
            onHintVisibilityChanged: { isVisible in
                resizeHint.isHidden = !isVisible
            },
            onResizeEnded: {
                onResizeEnded()
            }
        )
        addSubview(resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func label(
        _ value: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.maximumNumberOfLines = 1
        field.isSelectable = false
        return field
    }
}

@MainActor
private final class QuotaDetailHeightResizeHandleView: NSView {
    private let onResizeHeight: (CGFloat) -> Void
    private let onHintVisibilityChanged: (Bool) -> Void
    private let onResizeEnded: () -> Void
    private var startingHeight: CGFloat = 0
    private var startingScreenY: CGFloat = 0
    private var resizingWindow: NSWindow?
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isDragging = false

    init(
        frame frameRect: NSRect,
        accessibilityLabel: String,
        onResizeHeight: @escaping (CGFloat) -> Void,
        onHintVisibilityChanged: @escaping (Bool) -> Void,
        onResizeEnded: @escaping () -> Void
    ) {
        self.onResizeHeight = onResizeHeight
        self.onHintVisibilityChanged = onHintVisibilityChanged
        self.onResizeEnded = onResizeEnded
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .cursorUpdate,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        NSCursor.resizeUpDown.set()
        updateAppearance()
        updateHintVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateAppearance()
        updateHintVisibility()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        resizingWindow = window
        startingHeight = window.frame.height
        startingScreenY = window.convertPoint(toScreen: event.locationInWindow).y
        isDragging = true
        NSCursor.resizeUpDown.set()
        updateAppearance()
        updateHintVisibility()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resizingWindow else {
            return
        }
        let screenY = resizingWindow.convertPoint(
            toScreen: event.locationInWindow
        ).y
        onResizeHeight(startingHeight + startingScreenY - screenY)
    }

    override func mouseUp(with event: NSEvent) {
        resizingWindow = nil
        isDragging = false
        updateAppearance()
        updateHintVisibility()
        onResizeEnded()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let grip = CGRect(
            x: bounds.midX - 10,
            y: bounds.midY - 1,
            width: 20,
            height: 2
        )
        (isDragging ? NSColor.controlAccentColor : NSColor.separatorColor)
            .withAlphaComponent(isPointerInside || isDragging ? 0.9 : 0.72)
            .setFill()
        NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.labelColor
            .withAlphaComponent(isPointerInside || isDragging ? 0.07 : 0)
            .cgColor
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func updateHintVisibility() {
        onHintVisibilityChanged(isPointerInside || isDragging)
    }
}

@MainActor
private final class QuotaResizeHintView: NSView {
    private let text: String
    private let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.96)
            .cgColor
        layer?.borderColor = QuotaChromeStyle.separatorColor.cgColor
        layer?.borderWidth = QuotaChromeStyle.separatorLineWidth
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.16).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        setAccessibilityElement(false)
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return NSSize(
            width: max(74, ceil(textSize.width) + 18),
            height: 22
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textPoint = CGPoint(
            x: floor((bounds.width - textSize.width) / 2),
            y: floor((bounds.height - textSize.height) / 2)
        )
        (text as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class QuotaFooterView: NSView {
    private static let projectURL = URL(string: "https://github.com/JaceHwang/codex-usage-sidebar")!

    init(
        frame frameRect: NSRect,
        name: String?,
        avatarSeed: String?,
        avatarURL: URL?,
        informationEntry: QuotaInformationEntry,
        onOpenURL: @escaping (URL) -> Void,
        onSettingsButtonTapped: @escaping (NSButton) -> Void
    ) {
        super.init(frame: frameRect)
        let avatar = QuotaAvatarView(
            frame: CGRect(x: 18, y: 8, width: 28, height: 28),
            seed: avatarSeed,
            avatarURL: avatarURL
        )
        addSubview(avatar)

        let nameField = NSTextField(labelWithString: name ?? "Account")
        nameField.font = .systemFont(ofSize: 13, weight: .regular)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.frame = CGRect(
            x: 54,
            y: 14,
            width: max(0, frameRect.width - 258),
            height: 18
        )
        addSubview(nameField)

        let tibo = QuotaFooterLinkButton(
            frame: CGRect(x: frameRect.width - 204, y: 9, width: 72, height: 30),
            destination: informationEntry.destination,
            label: "Tibo",
            mark: QuotaFooterLinkButton.xMark,
            iconTint: .labelColor,
            accessibilityLabel: informationEntry.accessibilityLabel,
            onActivate: onOpenURL
        )
        tibo.toolTip = informationEntry.title
        addSubview(tibo)
        let github = QuotaFooterLinkButton(
            frame: CGRect(x: frameRect.width - 132, y: 9, width: 88, height: 30),
            destination: Self.projectURL,
            onActivate: onOpenURL
        )
        addSubview(github)
        let settings = QuotaFooterSettingsButton(
            frame: CGRect(x: frameRect.width - 44, y: 9, width: 30, height: 30),
            accessibilityLabel: "Settings"
        ) { button in
            onSettingsButtonTapped(button)
        }
        addSubview(settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class QuotaFooterLinkButton: NSButton {
    private static let projectMark: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <path fill="#000" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.084-.73.084-.73 1.205.084 1.84 1.237 1.84 1.237 1.07 1.834 2.807 1.304 3.492.997.108-.775.418-1.305.762-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.292-1.552 3.296-1.23 3.296-1.23.647 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.43.372.81 1.102.81 2.222 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.595 24 12.297c0-6.627-5.373-12-12-12"/>
        </svg>
        """
        return NSImage(data: Data(svg.utf8))
            ?? NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "GitHub")
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }()

    static let xMark: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <path fill="#000" d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.64 7.584H.47l8.6-9.835L0 1.154h7.594l5.243 6.932 6.064-6.933zm-1.29 19.49h2.039L6.487 3.24H4.3l13.31 17.403z"/>
        </svg>
        """
        return NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 16, height: 16))
    }()

    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private let iconTint: NSColor
    private let destination: URL
    private let onActivate: (URL) -> Void
    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    init(
        frame frameRect: NSRect,
        destination: URL,
        label: String = "GitHub",
        mark: NSImage? = nil,
        iconTint: NSColor = .secondaryLabelColor,
        accessibilityLabel: String = "GitHub",
        onActivate: @escaping (URL) -> Void
    ) {
        self.iconTint = iconTint
        self.destination = destination
        self.onActivate = onActivate
        iconView = NSImageView(image: mark ?? Self.projectMark)
        titleLabel = NSTextField(labelWithString: label)
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        contentTintColor = .secondaryLabelColor
        iconView.image?.isTemplate = true
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        target = self
        action = #selector(activateLink)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .left
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        addSubview(iconView)
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp(destination.absoluteString)
        updateAppearance()
    }

    @objc func activateLink() {
        onActivate(destination)
    }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(x: 10, y: 7, width: 16, height: 16)
        titleLabel.frame = CGRect(x: 32, y: 6, width: bounds.width - 40, height: 18)
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

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(isPointerInside ? 0.08 : 0)
                .cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isPointerInside ? 0.22 : 0
            layer?.shadowRadius = isPointerInside ? 8 : 0
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            iconView.contentTintColor = iconTint
            titleLabel.textColor = .secondaryLabelColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class QuotaFooterSettingsButton: NSButton {
    private let iconView: NSImageView
    private let onActivate: (QuotaFooterSettingsButton) -> Void
    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    init(
        frame frameRect: NSRect,
        accessibilityLabel: String,
        onActivate: @escaping (QuotaFooterSettingsButton) -> Void
    ) {
        iconView = NSImageView(
            image: NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: accessibilityLabel
            ) ?? NSImage(size: NSSize(width: 16, height: 16))
        )
        self.onActivate = onActivate
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        target = self
        action = #selector(activate)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image?.isTemplate = true
        addSubview(iconView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
        updateAppearance()
    }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(
            x: floor((bounds.width - 16) / 2),
            y: floor((bounds.height - 16) / 2),
            width: 16,
            height: 16
        )
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

    @objc private func activate() {
        onActivate(self)
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(isPointerInside ? 0.08 : 0)
                .cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isPointerInside ? 0.22 : 0
            layer?.shadowRadius = isPointerInside ? 8 : 0
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            iconView.contentTintColor = .secondaryLabelColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class QuotaReferenceTiboOutlineView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 10,
            yRadius: 10
        )
        QuotaChromeStyle.separatorColor.setStroke()
        outline.lineWidth = QuotaChromeStyle.separatorLineWidth
        outline.stroke()
    }
}

@MainActor
private final class VersionBadgeView: NSView {
    private let text: String
    private let font = NSFont.systemFont(
        ofSize: 12,
        weight: .medium
    )

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (text as NSString).size(
            withAttributes: [.font: font]
        )
        return NSSize(width: ceil(textSize.width) + 14, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let capsuleBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let capsule = NSBezierPath(
            roundedRect: capsuleBounds,
            xRadius: capsuleBounds.height / 2,
            yRadius: capsuleBounds.height / 2
        )
        QuotaChromeStyle.separatorColor.setStroke()
        capsule.lineWidth = QuotaChromeStyle.separatorLineWidth
        capsule.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textPoint = CGPoint(
            x: floor((bounds.width - textSize.width) / 2),
            y: floor((bounds.height - textSize.height) / 2)
        )
        (text as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class QuotaDetailLockButton: NSButton {
    private let iconView: NSImageView
    private let onActivate: () -> Void
    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    init(
        frame frameRect: NSRect,
        isLockedOpen: Bool,
        accessibilityLabel: String,
        onActivate: @escaping () -> Void
    ) {
        iconView = NSImageView()
        self.onActivate = onActivate
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        state = isLockedOpen ? .on : .off
        wantsLayer = true
        layer?.cornerRadius = frameRect.height / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        target = self
        action = #selector(activate)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
        updateAppearance()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        iconView.frame = CGRect(
            x: floor((bounds.width - 13) / 2),
            y: floor((bounds.height - 13) / 2),
            width: 13,
            height: 13
        )
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

    @objc private func activate() {
        onActivate()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isLockedOpen = state == .on
            let backgroundAlpha: CGFloat = isLockedOpen ? 0.12 : (isPointerInside ? 0.08 : 0)
            let tint: NSColor = isLockedOpen ? .controlAccentColor : .secondaryLabelColor
            layer?.backgroundColor = (isLockedOpen ? NSColor.controlAccentColor : NSColor.labelColor)
                .withAlphaComponent(backgroundAlpha)
                .cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isPointerInside ? 0.16 : 0
            layer?.shadowRadius = isPointerInside ? 5 : 0
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            iconView.image = NSImage(
                systemSymbolName: isLockedOpen ? "pin.fill" : "pin",
                accessibilityDescription: accessibilityLabel()
            )
            iconView.image?.isTemplate = true
            iconView.contentTintColor = tint
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
enum QuotaThemeIconAsset: Equatable {
    case dark
    case light

    var resourceName: String {
        switch self {
        case .dark:
            return "quota-icon-dark"
        case .light:
            return "quota-icon-light"
        }
    }

    static func forAppearance(_ appearance: NSAppearance?) -> Self {
        guard
            let appearance,
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        else {
            return .light
        }
        return .dark
    }
}

@MainActor
final class QuotaThemeIconView: NSView {
    private var iconImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        loadThemeIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        loadThemeIcon()
    }

    override var isOpaque: Bool { false }

    func updateAppearance(_ appearance: NSAppearance) {
        self.appearance = appearance
        appearance.performAsCurrentDrawingAppearance {
            loadThemeIcon()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        if let iconImage {
            iconImage.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            let fallback = NSColor.controlBackgroundColor
            fallback.setFill()
            circle.fill()
            NSColor.secondaryLabelColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
            ring.lineWidth = 3
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func loadThemeIcon() {
        let asset = QuotaThemeIconAsset.forAppearance(effectiveAppearance)
        let bundles = [Bundle.main, Bundle.module] + Bundle.allBundles + Bundle.allFrameworks
        iconImage = bundles.lazy.compactMap { bundle in
            let candidateURLs = [
                bundle.url(
                    forResource: asset.resourceName,
                    withExtension: "png"
                ),
                bundle.url(
                    forResource: asset.resourceName,
                    withExtension: "png",
                    subdirectory: "Resources"
                )
            ]
            return candidateURLs.lazy.compactMap { $0 }.compactMap {
                NSImage(contentsOf: $0)
            }.first
        }.first
        needsDisplay = true
    }
}

@MainActor
private final class QuotaAvatarView: NSView {
    private let seed: String?
    private let avatarURL: URL?
    private var remoteImage: NSImage?
    private var imageLoadTask: Task<Void, Never>?

    init(seed: String? = nil, avatarURL: URL? = nil) {
        self.seed = seed
        self.avatarURL = avatarURL
        super.init(frame: .zero)
        loadRemoteImageIfNeeded()
    }

    init(frame frameRect: NSRect, seed: String?, avatarURL: URL? = nil) {
        self.seed = seed
        self.avatarURL = avatarURL
        super.init(frame: frameRect)
        loadRemoteImageIfNeeded()
    }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, seed: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        imageLoadTask?.cancel()
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        let background = NSGradient(
            starting: NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.30, alpha: 1),
            ending: NSColor(calibratedRed: 0.27, green: 0.33, blue: 0.55, alpha: 1)
        )
        background?.draw(in: bounds, angle: 35)

        if let remoteImage {
            remoteImage.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
            NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
            circle.lineWidth = 0.75
            circle.stroke()
            return
        }

        if let seed, let initial = seed.first {
            NSGraphicsContext.restoreGraphicsState()
            let text = String(initial).uppercased() as NSString
            let font = NSFont.systemFont(
                ofSize: bounds.width * 0.38,
                weight: .semibold
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: floor((bounds.width - size.width) / 2),
                    y: floor((bounds.height - size.height) / 2)
                ),
                withAttributes: attributes
            )
            NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
            circle.lineWidth = 0.75
            circle.stroke()
            return
        }

        let shoulders = NSBezierPath(roundedRect: CGRect(
            x: bounds.midX - bounds.width * 0.33,
            y: bounds.minY - 2,
            width: bounds.width * 0.66,
            height: bounds.height * 0.48
        ), xRadius: bounds.width * 0.2, yRadius: bounds.width * 0.2)
        NSColor(calibratedRed: 0.72, green: 0.48, blue: 0.32, alpha: 1).setFill()
        shoulders.fill()

        let face = NSBezierPath(ovalIn: CGRect(
            x: bounds.midX - bounds.width * 0.22,
            y: bounds.midY - bounds.height * 0.24,
            width: bounds.width * 0.44,
            height: bounds.height * 0.54
        ))
        NSColor(calibratedRed: 0.83, green: 0.64, blue: 0.46, alpha: 1).setFill()
        face.fill()

        let hair = NSBezierPath(ovalIn: CGRect(
            x: bounds.midX - bounds.width * 0.30,
            y: bounds.midY - bounds.height * 0.33,
            width: bounds.width * 0.60,
            height: bounds.height * 0.62
        ))
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.07, alpha: 1).setFill()
        hair.fill()
        face.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
        circle.lineWidth = 0.75
        circle.stroke()
    }

    private func loadRemoteImageIfNeeded() {
        guard let avatarURL else {
            return
        }
        imageLoadTask = Task { [weak self] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: avatarURL),
                let image = NSImage(data: data)
            else {
                return
            }
            self?.remoteImage = image
            self?.needsDisplay = true
        }
    }
}

@MainActor
private enum QuotaDetailRowMetrics {
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let valueFont = NSFont.systemFont(ofSize: 12, weight: .regular)

    static func heights(
        for rows: [QuotaDetailRow],
        cardWidth: CGFloat,
        remainingPercent: Int
    ) -> [CGFloat] {
        rows.map { row in
            if row.value.contains("\n") {
                return 46
            }
            let labelWidth = min(118, textWidth(row.label, font: labelFont) + 2)
            let valueX = max(148, 42 + labelWidth + 10)
            let columnWidth = max(1, cardWidth - valueX - 12)
            let measuredValueWidth = ceil(
                QuotaDetailValueTypography.string(
                    for: row,
                    remainingPercent: remainingPercent
                ).size().width
            )
            guard measuredValueWidth > columnWidth else {
                return QuotaDetailLayout.rowHeight
            }

            let fullWidth = max(1, cardWidth - 54)
            let lineCount = max(1, Int(ceil(measuredValueWidth / fullWidth)))
            return 22 + CGFloat(lineCount) * 18
        }
    }

    private static func textWidth(_ value: String, font: NSFont) -> CGFloat {
        ceil(
            (value as NSString).size(
                withAttributes: [.font: font]
            ).width
        )
    }
}

@MainActor
private enum QuotaCountdownTypography {
    private static let digitFont = NSFont.systemFont(
        ofSize: 15,
        weight: .semibold
    )
    private static let unitFont = NSFont.systemFont(
        ofSize: 11,
        weight: .medium
    )
    private static let punctuationFont = NSFont.systemFont(
        ofSize: 10,
        weight: .regular
    )

    static func string(
        _ value: String,
        remainingPercent: Int
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let accentColor = QuotaColorScale.components(
            remainingPercent: remainingPercent
        ).appKitColor

        for segment in QuotaCountdownSegmenter.segments(in: value) {
            let attributes: [NSAttributedString.Key: Any]
            switch segment.role {
            case .plain:
                attributes = [
                    .font: QuotaDetailRowMetrics.valueFont,
                    .foregroundColor: NSColor.labelColor
                ]
            case .digits:
                attributes = [
                    .font: digitFont,
                    .foregroundColor: accentColor
                ]
            case .unit:
                attributes = [
                    .font: unitFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            case .punctuation, .suffix:
                attributes = [
                    .font: punctuationFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            }
            result.append(
                NSAttributedString(
                    string: segment.text,
                    attributes: attributes
                )
            )
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        result.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }
}

@MainActor
private enum QuotaDetailValueTypography {
    static func string(
        for row: QuotaDetailRow,
        remainingPercent: Int
    ) -> NSAttributedString {
        switch row.valueStyle {
        case .standard:
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            return NSAttributedString(
                string: row.value,
                attributes: [
                    .font: QuotaDetailRowMetrics.valueFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            )
        case .resetCountdown:
            return QuotaCountdownTypography.string(
                row.value,
                remainingPercent: remainingPercent
            )
        }
    }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class QuotaProgressView: NSView {
    private let value: Int

    init(frame frameRect: NSRect, value: Int) {
        self.value = min(100, max(0, value))
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        let fraction = CGFloat(value) / 100
        let fillRect = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.height, bounds.width * fraction),
            height: bounds.height
        )
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
        let stops = QuotaColorScale.progressGradientStops
        let colors = stops.map(\.components.appKitColor)
        let locations = stops.map { CGFloat($0.location) }
        let gradient = locations.withUnsafeBufferPointer {
            NSGradient(
                colors: colors,
                atLocations: $0.baseAddress,
                colorSpace: .deviceRGB
            )
        }
        NSGraphicsContext.saveGraphicsState()
        fill.addClip()
        gradient?.draw(in: bounds, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }
}
