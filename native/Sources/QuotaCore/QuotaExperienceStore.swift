import Foundation

public final class QuotaExperienceStore {
    private let url: URL
    public private(set) var corrupted = false
    public init(url: URL) { self.url = url }
    public func load() -> ExperienceState {
        guard FileManager.default.fileExists(atPath: url.path) else { return ExperienceState() }
        do {
            let state = try JSONDecoder().decode(ExperienceState.self, from: Data(contentsOf: url))
            guard state.schema == 1, !state.epoch.isEmpty, state.receipts.count <= 2048 else { throw CocoaError(.coderReadCorrupt) }
            return state
        } catch {
            corrupted = true
            // Preserve evidence without overwriting any older recovery copy.
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("\(UUID().uuidString).corrupt"))
            return ExperienceState()
        }
    }
    public func save(_ state: ExperienceState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
