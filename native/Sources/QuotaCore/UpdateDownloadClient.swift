import Foundation
import CryptoKit

public protocol UpdateTransport: Sendable {
    func metadata(_ url: URL, limit: Int) async throws -> Data
    func download(_ asset: UpdateAsset, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}
public struct DownloadedUpdate: Sendable {
    public let release: TrustedUpdateRelease
    public let directory: URL
    public let archive: URL
    public let provenance: URL
}
public enum UpdateFileIntegrity {
    public static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 65536), !bytes.isEmpty { try Task.checkCancellation(); hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ file: URL, asset: UpdateAsset) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == asset.size,
              try sha256(file) == asset.sha256 else { throw CocoaError(.fileReadCorruptFile) }
    }
    public static func provenance(_ bytes: Data, release: TrustedUpdateRelease) throws {
        struct Proof: Decodable { let kind: String; let version: String; let releaseTag: String; let sourceCommit: String; let workingTreeDirty: Bool }
        guard bytes.count <= 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let value = try JSONDecoder().decode(Proof.self, from: bytes)
        guard value.kind == "release", value.version == release.version, value.releaseTag == "v" + release.version,
              value.sourceCommit == release.sourceCommit, !value.workingTreeDirty else { throw CocoaError(.fileReadCorruptFile) }
    }
}
public struct UpdateDownloadClient: Sendable {
    private let transport: any UpdateTransport
    public init(transport: any UpdateTransport = UpdateHTTPTransport()) { self.transport = transport }
    public func download(version: String, platform: String, currentVersion: String, cache: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws -> DownloadedUpdate {
        let metadata = try await transport.metadata(TrustedUpdateRelease.apiURL(version: version), limit: 2 * 1024 * 1024)
        var tag = try await transport.metadata(TrustedUpdateRelease.tagURL(version: version), limit: 1024 * 1024)
        for _ in 0..<2 {
            struct Ref: Decodable { struct Object: Decodable { let type: String; let sha: String }; let object: Object }
            let ref = try JSONDecoder().decode(Ref.self, from: tag)
            if ref.object.type == "commit" { break }
            guard ref.object.type == "tag", TrustedUpdateRelease.hex(ref.object.sha, count: 40) else { throw CocoaError(.fileReadCorruptFile) }
            tag = try await transport.metadata(URL(string: "https://api.github.com/repos/\(TrustedUpdateRelease.repository)/git/tags/\(ref.object.sha)")!, limit: 1024 * 1024)
        }
        let release = try TrustedUpdateRelease.parse(releaseJSON: metadata, tagJSON: tag, version: version, platform: platform, currentVersion: currentVersion)
        try Task.checkCancellation()
        let fm = FileManager.default
        if fm.fileExists(atPath: cache.path), try fm.attributesOfItem(atPath: cache.path)[.type] as? FileAttributeType == .typeSymbolicLink { throw CocoaError(.fileWriteInvalidFileName) }
        try fm.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let free = (try fm.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard free > release.package.size + release.provenance.size + 64 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            let archive = directory.appendingPathComponent(release.package.name), proof = directory.appendingPathComponent(release.provenance.name)
            try await transport.download(release.package, to: archive, progress: { progress($0, release.package.size) })
            try Task.checkCancellation(); try UpdateFileIntegrity.verify(archive, asset: release.package)
            try await transport.download(release.provenance, to: proof, progress: { _ in })
            try Task.checkCancellation(); try UpdateFileIntegrity.verify(proof, asset: release.provenance)
            try UpdateFileIntegrity.provenance(Data(contentsOf: proof), release: release)
            try Task.checkCancellation()
            return DownloadedUpdate(release: release, directory: directory, archive: archive, provenance: proof)
        } catch { try? fm.removeItem(at: directory); throw error }
    }
}

/// Per-request delegate. It never shares redirect counters or credentials across downloads.
private final class UpdateTransferGuard: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let maximum: Int64
    let api: Bool
    let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var redirects = 0
    init(maximum: Int64, api: Bool = false, progress: @escaping @Sendable (Int64) -> Void = { _ in }) { self.maximum = maximum; self.api = api; self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); redirects += 1; let count = redirects; lock.unlock()
        guard !api, count <= 10, let url = request.url, TrustedUpdateRelease.allowedDownloadRedirect(url) else { completionHandler(nil); task.cancel(); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum { downloadTask.cancel(); return }
        progress(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
public final class UpdateHTTPTransport: UpdateTransport, @unchecked Sendable {
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 900
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel() }
    public func metadata(_ url: URL, limit: Int) async throws -> Data {
        guard url.scheme == "https", url.host == "api.github.com", url.port == nil, url.user == nil, url.password == nil, url.fragment == nil, url.query == nil,
              url.path.hasPrefix("/repos/\(TrustedUpdateRelease.repository)/") else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url); request.setValue("QuotaBar", forHTTPHeaderField: "User-Agent"); request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (bytes, response) = try await session.bytes(for: request, delegate: UpdateTransferGuard(maximum: Int64(limit), api: true))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url == url, response.expectedContentLength <= limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte) }
        return data
    }
    public func download(_ asset: UpdateAsset, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        guard asset.url.host == "github.com", asset.url.path.hasPrefix("/\(TrustedUpdateRelease.repository)/releases/download/"), asset.url.query == nil, TrustedUpdateRelease.allowedDownloadRedirect(asset.url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: asset.url); request.setValue("QuotaBar", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request, delegate: UpdateTransferGuard(maximum: asset.size, progress: progress))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        try Task.checkCancellation(); try UpdateFileIntegrity.verify(temporary, asset: asset)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
