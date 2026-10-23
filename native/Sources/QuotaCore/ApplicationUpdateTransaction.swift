import Foundation
import Darwin

public struct UpdateInstallJob: Codable, Sendable {
    public let schema: Int
    public let operationID: String
    public let target: String
    public let parentPID: Int32
    public let nonce: String
    public let expiresAt: Date
    public let release: TrustedUpdateRelease
    public init(operationID: String, target: String, parentPID: Int32, nonce: String, expiresAt: Date, release: TrustedUpdateRelease) {
        schema = 1; self.operationID = operationID; self.target = target; self.parentPID = parentPID; self.nonce = nonce; self.expiresAt = expiresAt; self.release = release
    }
    public func validate(directory: URL, expectedTarget: String, now: Date) throws {
        guard URL(fileURLWithPath: target).standardizedFileURL.path == URL(fileURLWithPath: expectedTarget).standardizedFileURL.path else { throw UpdatePackageError.invalidJobTarget }
        guard now < expiresAt, expiresAt.timeIntervalSince(now) <= 601 else { throw UpdatePackageError.expiredJob }
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("consumed").path) else { throw UpdatePackageError.consumedJob }
        guard schema == 1, UUID(uuidString: operationID) != nil, parentPID > 1, TrustedUpdateRelease.hex(nonce, count: 64), TrustedUpdateRelease.hex(release.sourceCommit, count: 40) else { throw UpdatePackageError.invalidJobIdentity }
        _ = try UpdateFeed.versionParts(release.version)
        _ = try MacUpdatePackage.treeBytes(directory)
    }
    public static func consumeResult(in cache: URL, expectedTarget: String) -> ApplicationUpdatePhase? {
        let fm = FileManager.default
        guard let paths = try? fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let recent = paths.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }.prefix(100)
        for path in recent {
            guard UUID(uuidString: path.lastPathComponent) != nil, !fm.fileExists(atPath: path.appendingPathComponent("presented").path),
                  let job = try? read(path), job.target == expectedTarget, Date().timeIntervalSince(job.expiresAt) < 86400 else { continue }
            for (kind, phase) in [("succeeded", ApplicationUpdatePhase.succeeded), ("rolledBack", .rolledBack), ("failed", .failed)] where job.hasReceipt(kind, directory: path) {
                guard (try? Data().write(to: path.appendingPathComponent("presented"), options: .atomic)) != nil else { return nil }
                return phase
            }
        }
        return nil
    }
    public func write(_ directory: URL) throws { try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("job.json"), options: .atomic) }
    public static func read(_ directory: URL) throws -> Self {
        let path = directory.appendingPathComponent("job.json")
        guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 65536 else { throw UpdatePackageError.invalidPackage }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: path))
    }
    public func receipt(_ kind: String, directory: URL) throws {
        guard ["ready", "handoff", "health", "succeeded", "rolledBack", "failed"].contains(kind) else { throw UpdatePackageError.invalidPackage }
        try JSONEncoder().encode(UpdateReceipt(schema: 1, operationID: operationID, nonce: nonce, kind: kind)).write(to: directory.appendingPathComponent(kind + ".json"), options: .atomic)
    }
    public func hasReceipt(_ kind: String, directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(kind + ".json")), data.count < 4096,
              let value = try? JSONDecoder().decode(UpdateReceipt.self, from: data) else { return false }
        return value.schema == 1 && value.operationID == operationID && value.nonce == nonce && value.kind == kind
    }
}
private struct UpdateReceipt: Codable { let schema: Int; let operationID: String; let nonce: String; let kind: String }
public enum UpdateLocations {
    public static var target: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/QuotaBar.app") }
    public static var cache: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.jace.codex-quota/Updates") }
    public static func directory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().path == cache.path, UUID(uuidString: url.lastPathComponent) != nil,
              url.resolvingSymlinksInPath().path == url.path else { throw UpdatePackageError.invalidPackage }
        return url
    }
    /// Called before any credential access. No network or settings reads are required.
    public static func acknowledgeHealth(arguments: [String], executable: String) throws {
        guard let index = arguments.firstIndex(of: "--update-health") else { return }
        guard arguments.count > index + 2, URL(fileURLWithPath: executable).standardizedFileURL == target.appendingPathComponent("Contents/MacOS/CodexQuota") else { throw UpdatePackageError.invalidIdentity }
        let directory = try directory(arguments[index + 1]), job = try UpdateInstallJob.read(directory)
        guard URL(fileURLWithPath: job.target).standardizedFileURL.path == target.standardizedFileURL.path, job.nonce == arguments[index + 2], Date() < job.expiresAt,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("consumed").path) else { throw UpdatePackageError.invalidPackage }
        try job.receipt("health", directory: directory)
    }
}
public final class ApplicationUpdateTransaction {
    private struct Journal: Codable { let backup: String; let stage: String; let operationDirectory: String? }
    private let target: URL, store: URL
    public init(target: URL) { self.target = target; store = target.deletingLastPathComponent().appendingPathComponent(".QuotaBar-update") }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard store.resolvingSymlinksInPath().path == store.path else { throw UpdatePackageError.linkedContent }
        let descriptor = open(store.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw UpdatePackageError.invalidPackage }; defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw UpdatePackageError.invalidPackage }; defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
    public static func recoveryJob(target: URL) throws -> URL? {
        let file = target.deletingLastPathComponent().appendingPathComponent(".QuotaBar-update/journal.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
        return journal.operationDirectory.map { URL(fileURLWithPath: $0) }
    }
    public func recover() throws { try locked { try restore() } }
    private func restore() throws {
        let fm = FileManager.default, path = store.appendingPathComponent("journal.json")
        guard fm.fileExists(atPath: path.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: path))
        for name in [journal.backup, journal.stage] {
            guard !name.contains("/"), !name.contains(".."), name.hasPrefix("backup-") || name.hasPrefix("stage-") else { throw UpdatePackageError.invalidPackage }
        }
        let backup = store.appendingPathComponent(journal.backup)
        if fm.fileExists(atPath: backup.path) {
            _ = try MacUpdatePackage.treeBytes(backup)
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: store.appendingPathComponent("failed-" + UUID().uuidString)) }
            try fm.moveItem(at: backup, to: target)
        }
        try fm.removeItem(at: path)
    }
    public func install(candidate: URL, operationDirectory: URL? = nil, validate: (URL) throws -> Void, health: () throws -> Void) throws {
        try locked {
            try restore(); let fm = FileManager.default
            guard candidate.standardizedFileURL != target.standardizedFileURL, !candidate.path.hasPrefix(target.path + "/"), fm.fileExists(atPath: target.path) else { throw UpdatePackageError.invalidIdentity }
            try validate(candidate)
            let stage = store.appendingPathComponent("stage-" + UUID().uuidString), backup = store.appendingPathComponent("backup-" + UUID().uuidString)
            try fm.copyItem(at: candidate, to: stage)
            do { try validate(stage) } catch { try? fm.removeItem(at: stage); throw error }
            let path = store.appendingPathComponent("journal.json")
            try JSONEncoder().encode(Journal(backup: backup.lastPathComponent, stage: stage.lastPathComponent, operationDirectory: operationDirectory?.path)).write(to: path, options: .atomic)
            do {
                try fm.moveItem(at: target, to: backup); try fm.moveItem(at: stage, to: target)
                try health(); try fm.removeItem(at: path)
            } catch { try restore(); throw error }
        }
    }
}

/// A cross-operation reservation is held before publishing ready; install's journal lock remains separate.
public final class UpdateHandoffReservation {
    private var descriptor: Int32
    public init(target: URL) throws {
        let store = target.deletingLastPathComponent().appendingPathComponent(".QuotaBar-update")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard store.resolvingSymlinksInPath().standardizedFileURL.path == store.standardizedFileURL.path else { throw UpdatePackageError.linkedContent }
        descriptor = open(store.appendingPathComponent("handoff.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw UpdatePackageError.invalidPackage }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); descriptor = -1; throw UpdatePackageError.invalidPackage }
    }
    public func release() { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 } }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
