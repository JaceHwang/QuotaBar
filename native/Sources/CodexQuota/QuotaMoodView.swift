import AppKit
import QuotaCore

@MainActor final class QuotaMoodView: NSView {
    var mood: QuotaMood = .unavailable { didSet { needsDisplay = true } }
    var usesEffectiveAppearance = false
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    var dark = false { didSet { needsDisplay = true } }
    var stars = false { didSet { needsDisplay = true } }
    var sparklePhase: Double = 0 { didSet { needsDisplay = true } }
    var showsCharacter = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.scaleBy(x: bounds.width/20, y: bounds.height/20)
        let dark = usesEffectiveAppearance ? effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua : dark
        let ink = dark ? NSColor(calibratedWhite: 0.9, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.21, alpha: 1)
        let fill: NSColor = switch mood {
        case .recovered: NSColor(calibratedRed: 0.74, green: 0.58, blue: 0.98, alpha: 1)
        case .good: NSColor(calibratedRed: 0.48, green: 0.88, blue: 0.66, alpha: 1)
        case .low: NSColor(calibratedRed: 1, green: 0.79, blue: 0.36, alpha: 1)
        case .exhausted: NSColor(calibratedRed: 0.98, green: 0.57, blue: 0.56, alpha: 1)
        case .unavailable: NSColor(calibratedWhite: 0.65, alpha: 1)
        }
        if showsCharacter {
            ink.setFill(); NSBezierPath(roundedRect: NSRect(x: 8, y: 16, width: 4, height: 3), xRadius: 1, yRadius: 1).fill()
            let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 3, width: 12, height: 14), xRadius: 3.2, yRadius: 3.2)
            fill.setFill(); body.fill(); ink.setStroke(); body.lineWidth = 1.2; body.stroke()
            NSColor.white.withAlphaComponent(0.4).setFill(); NSBezierPath(roundedRect: NSRect(x: 5.5, y: 8, width: 1.6, height: 6), xRadius: 0.8, yRadius: 0.8).fill()
            ink.setFill()
            if mood == .recovered {
                let arms = NSBezierPath(); arms.move(to: NSPoint(x: 4, y: 9)); arms.line(to: NSPoint(x: 1.8, y: 12)); arms.line(to: NSPoint(x: 1.5, y: 14))
                arms.move(to: NSPoint(x: 16, y: 9)); arms.line(to: NSPoint(x: 18.2, y: 12)); arms.line(to: NSPoint(x: 18.5, y: 14)); arms.lineWidth = 1.5; ink.setStroke(); arms.stroke()
            } else {
                NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 3, height: 3)).fill(); NSBezierPath(ovalIn: NSRect(x: 15, y: 6, width: 3, height: 3)).fill()
            }
            NSBezierPath(roundedRect: NSRect(x: 6, y: 1.5, width: 2.8, height: 2), xRadius: 0.8, yRadius: 0.8).fill(); NSBezierPath(roundedRect: NSRect(x: 11, y: 1.5, width: 2.8, height: 2), xRadius: 0.8, yRadius: 0.8).fill()
            let face = NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.21, alpha: 1)
            face.setFill(); face.setStroke()
            if mood == .recovered {
                NSColor.systemYellow.setFill(); face.setStroke()
                for x in [7.5, 12.0] {
                    let star = NSBezierPath()
                    for i in 0..<10 {
                        let angle = Double(i) * .pi / 5 + .pi / 2
                        let radius = i % 2 == 0 ? 2.4 : 1.05
                        let p = NSPoint(x: x + cos(angle)*radius, y: 11 + sin(angle)*radius)
                        if i == 0 { star.move(to: p) } else { star.line(to: p) }
                    }
                    star.close(); star.fill(); star.lineWidth = 0.45; star.stroke()
                }
                face.setFill(); NSBezierPath(ovalIn: NSRect(x: 8, y: 5, width: 4, height: 3.5)).fill()
                NSColor.systemPink.setFill(); NSBezierPath(ovalIn: NSRect(x: 9, y: 5.2, width: 2, height: 1.2)).fill()
            } else if mood == .unavailable {
                let text: NSString = "?"; text.draw(at: NSPoint(x: 7, y: 6), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: face])
            } else {
                for x in [7.2, 11.2] {
                    if mood == .exhausted { let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 11)); p.line(to: NSPoint(x: x+1.5, y: 10)); p.lineWidth = 1; p.stroke() }
                    else { NSBezierPath(ovalIn: NSRect(x: x, y: 10.5, width: 1.6, height: 1.8)).fill() }
                }
                let mouth = NSBezierPath(); mouth.move(to: NSPoint(x: 8.4, y: 8))
                mouth.curve(to: NSPoint(x: 11.6, y: 8), controlPoint1: NSPoint(x: 9, y: mood == .good || mood == .recovered ? 5.7 : 9), controlPoint2: NSPoint(x: 11, y: mood == .good || mood == .recovered ? 5.7 : 9)); mouth.lineWidth = 1; mouth.stroke()
            }
        }
        if stars {
            NSColor.systemYellow.withAlphaComponent(0.65 + 0.35 * abs(sin(sparklePhase))).setFill()
            for (x,y) in [(2.0,16.0),(18.0,13.0),(17.5,3.0)] {
                let p = NSBezierPath(); p.move(to: NSPoint(x:x,y:y+2)); p.line(to:NSPoint(x:x+0.7,y:y+0.7)); p.line(to:NSPoint(x:x+2,y:y)); p.line(to:NSPoint(x:x+0.7,y:y-0.7)); p.line(to:NSPoint(x:x,y:y-2)); p.line(to:NSPoint(x:x-0.7,y:y-0.7)); p.line(to:NSPoint(x:x-2,y:y)); p.line(to:NSPoint(x:x-0.7,y:y+0.7)); p.close(); p.fill()
            }
        }
    }
}
@MainActor final class RecoveryCelebrationController {
    private var timer: Timer?
    private var deadline: Date?
    var onChange: ((Bool, Double) -> Void)?
    var active: Bool { deadline != nil }
    func play(visible: Bool) {
        guard visible, !active else { return }
        let start = Date(); deadline = start.addingTimeInterval(2); onChange?(true, 0)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        timer = Timer(timeInterval: reduced ? 2 : 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let deadline = self.deadline else { return }
                if Date() >= deadline { self.cancel() } else { self.onChange?(true, Date().timeIntervalSince(start)*8) }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func cancel() { timer?.invalidate(); timer = nil; deadline = nil; onChange?(false, 0) }
}
