import AppKit
import QuotaCore

@MainActor
extension QuotaColorComponents {
    var appKitColor: NSColor {
        NSColor(
            calibratedHue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: 1
        )
    }
}
