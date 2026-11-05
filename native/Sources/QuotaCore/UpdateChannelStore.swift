import Foundation
import Darwin

public final class UpdateChannelStore {
    private struct State: Codable { let schema: Int; let betaEnabled: Bool }
    private let url: URL
    public init(url: URL) { self.url = url }

    private func read() throws -> State {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard let raw = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let compact = String(raw.filter { !$0.isWhitespace })
        let allowed = ["{\"schema\":1,\"betaEnabled\":true}", "{\"schema\":1,\"betaEnabled\":false}", "{\"betaEnabled\":true,\"schema\":1}", "{\"betaEnabled\":false,\"schema\":1}"]
        guard allowed.contains(compact) else { throw CocoaError(.fileReadCorruptFile) }
        let state = try JSONDecoder().decode(State.self, from: data)
        guard state.schema == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }

    private func quarantine() throws {
        let destination = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".corrupt-" + UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: destination)
    }

    public func load() -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do { return try read().betaEnabled }
        catch { try? quarantine(); return false }
    }

    public func save(enabled: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            do { _ = try read() }
            catch { try quarantine() }
        }
        let bytes = try JSONEncoder().encode(State(schema: 1, betaEnabled: enabled))
        let temporary = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".tmp")
        defer { try? fm.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
