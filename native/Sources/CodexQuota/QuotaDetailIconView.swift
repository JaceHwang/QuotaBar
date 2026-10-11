import AppKit

@MainActor
enum QuotaDetailIconKind {
    case plan
    case quotaWindow
    case reset
    case credits
    case bank
    case refresh

    static func kind(forRowAt index: Int, count: Int) -> QuotaDetailIconKind {
        if index == count - 1 { return .refresh }
        switch index {
        case 0: return .plan
        case 1: return .quotaWindow
        case 2: return .reset
        case 3: return .credits
        default: return .bank
        }
    }

    static func kind(forRowLabel label: String, index: Int, count: Int) -> QuotaDetailIconKind {
        let normalized = label.lowercased()
        if normalized.contains("额度周期") ||
            normalized.contains("額度週期") ||
            normalized.contains("quota window")
        {
            return .quotaWindow
        }
        if normalized.contains("重置") ||
            normalized.contains("重設") ||
            normalized.contains("reset")
        {
            return .reset
        }
        if normalized == "credits" {
            return .credits
        }
        if normalized.contains("bank") {
            return .bank
        }
        if normalized.contains("更新") ||
            normalized == "updated"
        {
            return .refresh
        }
        return kind(forRowAt: index, count: count)
    }
}

@MainActor
final class QuotaDetailIconView: NSView {
    private let kind: QuotaDetailIconKind

    init(kind: QuotaDetailIconKind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = NSColor.secondaryLabelColor
        color.setStroke()
        let insetBounds = bounds.insetBy(dx: 2, dy: 2)

        switch kind {
        case .plan:
            drawPlan(in: insetBounds)
        case .quotaWindow:
            drawCalendar(in: insetBounds)
        case .reset:
            drawClock(in: insetBounds)
        case .credits:
            drawCredits(in: insetBounds)
        case .bank:
            drawBank(in: insetBounds)
        case .refresh:
            drawRefresh(in: insetBounds)
        }
    }

    private func stroke(_ path: NSBezierPath) {
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawPlan(in rect: CGRect) {
        stroke(NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5))
        let y = rect.midY
        let rule = NSBezierPath()
        rule.move(to: CGPoint(x: rect.minX + 2, y: y))
        rule.line(to: CGPoint(x: rect.maxX - 2, y: y))
        stroke(rule)
    }

    private func drawCalendar(in rect: CGRect) {
        stroke(NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5))
        let header = NSBezierPath()
        header.move(to: CGPoint(x: rect.minX, y: rect.maxY - 5))
        header.line(to: CGPoint(x: rect.maxX, y: rect.maxY - 5))
        header.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY + 1))
        header.line(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 3))
        header.move(to: CGPoint(x: rect.maxX - 4, y: rect.maxY + 1))
        header.line(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 3))
        stroke(header)
    }

    private func drawClock(in rect: CGRect) {
        stroke(NSBezierPath(ovalIn: rect))
        let hands = NSBezierPath()
        hands.move(to: CGPoint(x: rect.midX, y: rect.midY))
        hands.line(to: CGPoint(x: rect.midX, y: rect.maxY - 4))
        hands.move(to: CGPoint(x: rect.midX, y: rect.midY))
        hands.line(to: CGPoint(x: rect.maxX - 4, y: rect.midY - 2))
        stroke(hands)
    }

    private func drawCredits(in rect: CGRect) {
        let top = CGRect(x: rect.minX, y: rect.maxY - 7, width: rect.width, height: 6)
        stroke(NSBezierPath(ovalIn: top))
        let body = NSBezierPath()
        body.move(to: CGPoint(x: rect.minX, y: rect.maxY - 4))
        body.line(to: CGPoint(x: rect.minX, y: rect.minY + 4))
        body.curve(
            to: CGPoint(x: rect.maxX, y: rect.minY + 4),
            controlPoint1: CGPoint(x: rect.minX + 2, y: rect.minY),
            controlPoint2: CGPoint(x: rect.maxX - 2, y: rect.minY)
        )
        body.line(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
        stroke(body)
        let middle = NSBezierPath()
        middle.move(to: CGPoint(x: rect.minX, y: rect.midY))
        middle.curve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            controlPoint1: CGPoint(x: rect.minX + 3, y: rect.midY - 3),
            controlPoint2: CGPoint(x: rect.maxX - 3, y: rect.midY - 3)
        )
        stroke(middle)
    }

    private func drawBank(in rect: CGRect) {
        let roof = NSBezierPath()
        roof.move(to: CGPoint(x: rect.minX, y: rect.maxY - 5))
        roof.line(to: CGPoint(x: rect.midX, y: rect.maxY))
        roof.line(to: CGPoint(x: rect.maxX, y: rect.maxY - 5))
        roof.close()
        stroke(roof)
        let base = NSBezierPath()
        base.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 2))
        base.line(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 2))
        for fraction in [0.25, 0.5, 0.75] {
            let x = rect.minX + rect.width * fraction
            base.move(to: CGPoint(x: x, y: rect.minY + 3))
            base.line(to: CGPoint(x: x, y: rect.maxY - 6))
        }
        stroke(base)
    }

    private func drawRefresh(in rect: CGRect) {
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2 - 1,
            startAngle: 34,
            endAngle: 318,
            clockwise: false
        )
        stroke(arc)
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: rect.maxX - 1, y: rect.midY + 3))
        arrow.line(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 3))
        arrow.line(to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 3))
        stroke(arrow)
    }
}
