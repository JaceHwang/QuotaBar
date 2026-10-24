import Foundation
public final class QuotaWarningStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> QuotaWarningState {
        guard FileManager.default.fileExists(atPath: url.path) else { return QuotaWarningState() }
        do {
            let state = try JSONDecoder().decode(QuotaWarningState.self, from: Data(contentsOf: url))
            guard state.schema == 1, state.periods.count <= 2 else { throw CocoaError(.coderReadCorrupt) }
            return state
        } catch {
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("\(UUID()).corrupt"))
            return QuotaWarningState()
        }
    }
    public func save(_ state: QuotaWarningState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
