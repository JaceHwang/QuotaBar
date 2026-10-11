import Foundation

@MainActor
final class QuotaExternalLinkActivator {
    private let dismiss: () -> Void
    private let open: (URL) -> Bool

    init(
        dismiss: @escaping () -> Void,
        open: @escaping (URL) -> Bool
    ) {
        self.dismiss = dismiss
        self.open = open
    }

    func activate(_ destination: URL) {
        dismiss()
        _ = open(destination)
    }
}
