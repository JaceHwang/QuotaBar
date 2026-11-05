import AppKit

@MainActor final class BetaSettingsCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero); wantsLayer = true; layer?.cornerRadius = 10; layer?.borderWidth = 0.75
        addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: topAnchor, constant: 8), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
        colors()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        }
    }
}
