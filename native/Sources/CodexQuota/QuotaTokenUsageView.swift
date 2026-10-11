import AppKit
import QuotaCore

@MainActor
final class QuotaTokenUsageView: NSView {
    private static let titleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    private static let totalFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let noteFont = NSFont.systemFont(ofSize: 9, weight: .regular)

    let barCount: Int

    init(
        frame frameRect: NSRect,
        presentation: QuotaTokenUsagePresentation,
        remainingPercent: Int
    ) {
        let displayDays = Array(presentation.days.prefix(7))
        barCount = displayDays.count
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(presentation.title)
        setAccessibilityValue(
            presentation.availability == .available
                ? presentation.totalLabel
                : presentation.delayNote
        )

        let title = label(
            presentation.title,
            font: Self.titleFont,
            color: .labelColor,
            alignment: .left
        )
        title.frame = CGRect(
            x: 0,
            y: bounds.height - 25,
            width: 120,
            height: 20
        )
        addSubview(title)

        let total = label(
            presentation.totalLabel,
            font: Self.totalFont,
            color: .secondaryLabelColor,
            alignment: .right
        )
        total.lineBreakMode = .byTruncatingHead
        total.frame = CGRect(
            x: 120,
            y: bounds.height - 24,
            width: max(0, bounds.width - 120),
            height: 16
        )
        addSubview(total)

        if presentation.availability != .available {
            let note = label(
                presentation.delayNote,
                font: Self.noteFont,
                color: .tertiaryLabelColor,
                alignment: .left
            )
            note.lineBreakMode = .byTruncatingTail
            note.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 12)
            addSubview(note)
        }

        guard !displayDays.isEmpty else {
            return
        }

        let chart = TokenUsageChartView(
            frame: CGRect(
                x: 0,
                y: 24,
                width: bounds.width,
                height: 86
            ),
            days: displayDays,
            remainingPercent: remainingPercent
        )
        addSubview(chart)

        // The native compact popover intentionally omits the secondary daily
        // label and chart legend; the seven columns carry the complete signal.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func label(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.maximumNumberOfLines = 1
        field.isSelectable = false
        return field
    }
}

@MainActor
private final class TokenUsageChartView: NSView {
    init(
        frame frameRect: NSRect,
        days: [QuotaTokenUsageDay],
        remainingPercent: Int
    ) {
        super.init(frame: frameRect)
        let maximum = max(1, days.map(\.tokens).max() ?? 0)
        let columnWidth = bounds.width / CGFloat(max(1, days.count))
        for (index, day) in days.enumerated() {
            let height = day.tokens > 0
                ? max(3, floor(30 * CGFloat(day.tokens) / CGFloat(maximum)))
                : 0
            let bar = QuotaTokenUsageBarView(
                frame: CGRect(
                    x: CGFloat(index) * columnWidth,
                    y: 0,
                    width: columnWidth,
                    height: bounds.height
                ),
                day: day,
                barHeight: height,
                remainingPercent: remainingPercent
            )
            addSubview(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class QuotaTokenUsageBarView: NSView {
    private let day: QuotaTokenUsageDay
    private let barHeight: CGFloat
    private let remainingPercent: Int
    private let numberFont = NSFont.systemFont(ofSize: 10, weight: .regular)
    private let dateFont = NSFont.systemFont(ofSize: 10, weight: .regular)

    init(
        frame frameRect: NSRect,
        day: QuotaTokenUsageDay,
        barHeight: CGFloat,
        remainingPercent: Int
    ) {
        self.day = day
        self.barHeight = barHeight
        self.remainingPercent = remainingPercent
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(day.label)
        setAccessibilityValue(Self.tokenLabel(day.tokens))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let accent = QuotaColorScale.components(
            remainingPercent: remainingPercent
        ).appKitColor
        let labelColor: NSColor = day.isCurrentDay ? accent : .secondaryLabelColor
        let value = Self.tokenLabel(day.tokens) as NSString
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: labelColor
        ]
        let valueSize = value.size(withAttributes: valueAttributes)
        value.draw(
            at: CGPoint(
                x: floor((bounds.width - valueSize.width) / 2),
                y: bounds.height - valueSize.height - 14
            ),
            withAttributes: valueAttributes
        )

        if barHeight > 0 {
            let fillColor: NSColor = day.isCurrentDay
                ? accent
                : NSColor.secondaryLabelColor.withAlphaComponent(0.38)
            let barRect = CGRect(
                x: floor((bounds.width - 12) / 2),
                y: 15,
                width: 12,
                height: min(barHeight, max(3, bounds.height - 34))
            )
            let path = NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3)
            fillColor.setFill()
            path.fill()
        }

        let date = day.label as NSString
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let dateSize = date.size(withAttributes: dateAttributes)
        date.draw(
            at: CGPoint(
                x: floor((bounds.width - dateSize.width) / 2),
                y: -2
            ),
            withAttributes: dateAttributes
        )
    }

    private static func tokenLabel(_ tokens: Int64) -> String {
        switch tokens {
        case 1_000_000...:
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", Double(tokens) / 1_000)
        default:
            return String(tokens)
        }
    }
}

@MainActor
final class TokenUsageLegendView: NSView {
    let totalLabel: String
    let dailyLabel: String
    private let accent: NSColor
    private let font = NSFont.systemFont(ofSize: 9, weight: .regular)

    init(frame frameRect: NSRect, totalLabel: String, dailyLabel: String, accent: NSColor) {
        self.totalLabel = totalLabel
        self.dailyLabel = dailyLabel
        self.accent = accent
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawItem(text: totalLabel, at: 0, color: .secondaryLabelColor.withAlphaComponent(0.55))
        let firstWidth = (totalLabel as NSString).size(withAttributes: [.font: font]).width
        drawItem(text: dailyLabel, at: firstWidth + 42, color: accent)
    }

    private func drawItem(text: String, at x: CGFloat, color: NSColor) {
        let swatch = NSBezierPath(
            roundedRect: CGRect(x: x, y: 2, width: 9, height: 9),
            xRadius: 2,
            yRadius: 2
        )
        color.setFill()
        swatch.fill()
        (text as NSString).draw(
            at: CGPoint(x: x + 14, y: 1),
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }
}
