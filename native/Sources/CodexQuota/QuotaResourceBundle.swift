import Foundation

@MainActor
enum QuotaResourceBundle {
    static func resolve(main: Bundle = .main, module: () -> Bundle = { .module }) -> Bundle? {
        // Installed apps use the standard AppKit resource directory. Do not evaluate
        // SwiftPM's generated accessor here: some toolchains hard-code the build tree.
        if let directory = main.resourceURL,
           let packaged = Bundle(url: directory.appendingPathComponent("CodexQuota_CodexQuota.bundle")) {
            return packaged
        }
        if main.bundleURL.pathExtension == "app" { return nil }
        return module()
    }
}
