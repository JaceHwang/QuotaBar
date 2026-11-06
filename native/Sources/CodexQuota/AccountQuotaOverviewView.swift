import AppKit
import QuotaCore

/// The settings overview consumes the same formatted snapshot as the popover.
@MainActor final class AccountQuotaOverviewView: NSView {
    private let copy: ExperienceCopy
    private let notice = QuotaSettingsStyle.label("", secondary: true)
    private var content: QuotaDetailContent?
    private var metrics: [AccountQuotaMetric] = []
    private var bank: AccountQuotaFacts?
    private var tokenCard: AccountOverviewCard?
    private var tokenChart: QuotaTokenUsageView?
    private let missingTokens = QuotaSettingsStyle.label("", size: 14, secondary: true)
    private var chartSize = NSSize.zero
    private var measuredHeight: CGFloat = 120
    private var lastStateText: String?
    private var lastCurrent: Bool?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight) }

    init(language: CodexDisplayLanguage) {
        copy = ExperienceCopy(language)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 120))
        identifier = .init("account.quotaOverview")
        notice.identifier = .init("account.quotaState")
        addSubview(notice)
        setContentHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { nil }

    func update(content: QuotaDetailContent?, stateText: String, current: Bool) {
        guard self.content != content || lastStateText != stateText || lastCurrent != current else { return }
        lastStateText = stateText; lastCurrent = current
        self.content = content
        metrics.forEach { $0.removeFromSuperview() }
        bank?.removeFromSuperview(); tokenCard?.removeFromSuperview()
        metrics = []; tokenChart = nil; chartSize = .zero
        notice.stringValue = content == nil || !current ? stateText : ""
        notice.isHidden = notice.stringValue.isEmpty
        if let content {
            for (index, window) in content.quotaWindows.enumerated() {
                let reset = content.windowResetRows.indices.contains(index) ? content.windowResetRows[index] : nil
                let metric = AccountQuotaMetric(window: window, reset: reset, current: current)
                metric.identifier = .init("account.quota.\(index)")
                addSubview(metric); metrics.append(metric)
            }
            let facts = content.bankRows + [QuotaDetailRow(label: "Credits", value: content.creditsSummary ?? "—")]
            let bank = AccountQuotaFacts(title: copy.text("Bank & credits", "Bank 权益与 Credits", "Bank 權益與 Credits"), rows: facts)
            self.bank = bank; addSubview(bank)
            let token = AccountOverviewCard()
            token.identifier = .init("account.tokens")
            tokenCard = token; addSubview(token)
            missingTokens.removeFromSuperview()
            if content.tokenUsage == nil {
                missingTokens.stringValue = copy.text("Token usage\nUnavailable", "Token 用量\n暂无数据", "Token 用量\n暫無資料")
                token.addSubview(missingTokens)
            }
        } else {
            bank = nil; tokenCard = nil
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let width = max(180, bounds.width)
        var y: CGFloat = 0
        if !notice.isHidden {
            notice.preferredMaxLayoutWidth = width
            let height = max(24, notice.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 24)
            notice.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height + 12
        }
        if content != nil {
            let columns = width >= 480 ? max(1, metrics.count) : 1
            let metricWidth = (width - CGFloat(columns - 1) * 14) / CGFloat(columns)
            let metricHeight = metrics.map { $0.height(for: metricWidth) }.max() ?? 0
            for (index, metric) in metrics.enumerated() {
                metric.frame = NSRect(x: CGFloat(index % columns) * (metricWidth + 14), y: y + CGFloat(index / columns) * (metricHeight + 14), width: metricWidth, height: metricHeight)
            }
            if !metrics.isEmpty { y += CGFloat((metrics.count + columns - 1) / columns) * (metricHeight + 14) }
            if let bank, let tokenCard {
                let split = width >= 760
                let bankWidth = split ? width * 0.36 : width
                let tokenWidth = split ? width - bankWidth - 14 : width
                let bankHeight = bank.height(for: bankWidth)
                let height = max(230, bankHeight)
                tokenCard.frame = NSRect(x: 0, y: y, width: tokenWidth, height: split ? height : 230)
                bank.frame = NSRect(x: split ? tokenWidth + 14 : 0, y: split ? y : y + 244, width: bankWidth, height: split ? height : bankHeight)
                let size = NSSize(width: max(100, tokenWidth - 32), height: tokenCard.bounds.height - 32)
                missingTokens.frame = NSRect(x: 16, y: 16, width: size.width, height: 60)
                if size != chartSize {
                    tokenChart?.removeFromSuperview()
                    if let usage = content?.tokenUsage {
                        let chart = QuotaTokenUsageView(frame: NSRect(origin: NSPoint(x: 16, y: 16), size: size), presentation: usage, remainingPercent: content?.remainingPercent ?? 0, expanded: true)
                        tokenCard.addSubview(chart); tokenChart = chart
                    }
                    chartSize = size
                }
                y += split ? height : 244 + bankHeight
            }
        } else { y = max(y, 86) }
        let height = ceil(y)
        if height != measuredHeight { measuredHeight = height; invalidateIntrinsicContentSize() }
    }
}

@MainActor private class AccountOverviewCard: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.borderWidth = 0.5
        colors()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

@MainActor private final class AccountQuotaMetric: AccountOverviewCard {
    private let title: NSTextField
    private let value: NSTextField
    private let reset: NSTextField
    private let progress: AccountQuotaProgress
    init(window: QuotaWindowPresentation, reset: QuotaDetailRow?, current: Bool) {
        title = QuotaSettingsStyle.label(window.label, size: 14)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        value = QuotaSettingsStyle.label("\(window.remainingPercent)%", size: 32)
        value.font = .systemFont(ofSize: 32, weight: .semibold)
        value.textColor = current ? QuotaColorScale.components(remainingPercent: window.remainingPercent).appKitColor : .secondaryLabelColor
        self.reset = QuotaSettingsStyle.label(reset.map { $0.label + "\n" + $0.value } ?? "—", size: 12, secondary: true)
        progress = AccountQuotaProgress(percent: window.remainingPercent)
        super.init(frame: .zero)
        for view in [title, value, self.reset, progress] { addSubview(view) }
        value.identifier = .init("account.quota.percent")
        self.reset.identifier = .init("account.quota.reset")
    }
    required init?(coder: NSCoder) { nil }
    func height(for width: CGFloat) -> CGFloat {
        reset.preferredMaxLayoutWidth = max(80, width - 32)
        let size = reset.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 32, height: 1000)).height ?? 44
        return max(164, 122 + ceil(size))
    }
    override func layout() {
        super.layout()
        let width = max(80, bounds.width - 32)
        title.frame = NSRect(x: 16, y: 14, width: width, height: 22)
        value.frame = NSRect(x: 16, y: 39, width: width, height: 42)
        progress.frame = NSRect(x: 16, y: 90, width: width, height: 6)
        reset.frame = NSRect(x: 16, y: 110, width: width, height: max(44, bounds.height - 122))
    }
}

@MainActor private final class AccountQuotaProgress: NSView {
    let percent: Int
    init(percent: Int) { self.percent = percent; super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityLabel("\(percent)%") }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * CGFloat(min(100, max(0, percent))) / 100, height: bounds.height), xRadius: 3, yRadius: 3).fill()
    }
}

@MainActor private final class AccountQuotaFacts: AccountOverviewCard {
    private let title: NSTextField
    private let pairs: [(NSTextField, NSTextField)]
    init(title: String, rows: [QuotaDetailRow]) {
        self.title = QuotaSettingsStyle.label(title, size: 15)
        self.title.font = .systemFont(ofSize: 15, weight: .semibold)
        pairs = rows.map { row in
            let name = QuotaSettingsStyle.label(row.label, size: 11, secondary: true)
            let value = QuotaSettingsStyle.label(row.value, size: 13)
            value.isSelectable = true
            return (name, value)
        }
        super.init(frame: .zero)
        identifier = .init("account.bank")
        addSubview(self.title)
        for (name, value) in pairs { addSubview(name); addSubview(value) }
    }
    required init?(coder: NSCoder) { nil }
    func height(for width: CGFloat) -> CGFloat { arrange(width: width, apply: false) }
    private func arrange(width: CGFloat, apply: Bool) -> CGFloat {
        let inner = max(80, width - 32)
        let nameWidth = min(112, inner * 0.42)
        let valueWidth = inner - nameWidth - 8
        var y: CGFloat = 48
        if apply { title.frame = NSRect(x: 16, y: 14, width: inner, height: 24) }
        for (name, value) in pairs {
            name.preferredMaxLayoutWidth = nameWidth
            value.preferredMaxLayoutWidth = valueWidth
            value.alignment = .right
            let labelHeight = ceil(name.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: nameWidth, height: 10000)).height ?? 18)
            let height = max(24, labelHeight, ceil(value.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: valueWidth, height: 10000)).height ?? 20))
            if apply {
                name.frame = NSRect(x: 16, y: y, width: nameWidth, height: height)
                value.frame = NSRect(x: 24 + nameWidth, y: y, width: valueWidth, height: height)
            }
            y += height + 12
        }
        return y + 4
    }
    override func layout() { super.layout(); _ = arrange(width: bounds.width, apply: true) }
}

@MainActor final class AccountIdentityHeaderView: NSView {
    let name = QuotaSettingsStyle.label("", size: 16)
    let plan = QuotaSettingsStyle.label("", size: 12, secondary: true)
    let status = QuotaSettingsStyle.label("", size: 12, secondary: true)
    private let icon = NSImageView(image: NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!)
    private var measuredHeight: CGFloat = 54
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.maximumNumberOfLines = 1; name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        for view in [name, plan, status, icon] { addSubview(view) }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        let narrow = bounds.width < 570
        let leftWidth = narrow ? max(80, bounds.width - 48) : max(80, bounds.width * 0.55 - 48)
        icon.frame = NSRect(x: 0, y: 7, width: 34, height: 34)
        name.frame = NSRect(x: 48, y: 2, width: leftWidth, height: 24)
        plan.frame = NSRect(x: 48, y: 29, width: leftWidth, height: 20)
        status.alignment = narrow ? .left : .right
        let statusWidth = narrow ? max(80, bounds.width - 48) : bounds.width * 0.45
        status.preferredMaxLayoutWidth = statusWidth
        let statusHeight = max(36, ceil(status.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: statusWidth, height: 1000)).height ?? 36))
        status.frame = NSRect(x: narrow ? 48 : bounds.width * 0.55, y: narrow ? 55 : 8, width: statusWidth, height: statusHeight)
        let height = narrow ? 58 + statusHeight : max(54, statusHeight + 16)
        if height != measuredHeight { measuredHeight = height; invalidateIntrinsicContentSize() }
    }
}
