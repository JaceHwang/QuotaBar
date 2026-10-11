import AppKit
import QuotaCore

@MainActor
extension CodexInterfaceTheme {
    var appKitAppearance: NSAppearance {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua) ?? NSApplication.shared.effectiveAppearance
    }
}
