import Foundation
import Darwin

/// Holds the reservation until verified assets have been copied to a new job.
final class UpdateDownloadCache {
    private let root: URL
    private let directory: URL
    private let reservation: Int32

    init(root: URL) throws {
        self.root = root
        directory = root.appendingPathComponent("downloads", isDirectory: true)
        try Self.rejectLink(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.rejectLink(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("download.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw CocoaError(.fileWriteUnknown)
        }
        reservation = fd
    }
    deinit { flock(reservation, LOCK_UN); close(reservation) }

    static func rejectLink(_ url: URL) throws {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if attrs[.type] as? FileAttributeType == .typeSymbolicLink { throw CocoaError(.fileWriteInvalidFileName) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
    }

    func get(_ asset: UpdateAsset, transport: any UpdateTransport, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let fm = FileManager.default, path = directory.appendingPathComponent(asset.sha256)
        try Self.rejectLink(path)
        if fm.fileExists(atPath: path.path) {
            let size = (try fm.attributesOfItem(atPath: path.path)[.size] as? NSNumber)?.int64Value ?? -1
            if size >= asset.size {
                do { try UpdateFileIntegrity.verify(path, asset: asset); progress(asset.size); return path }
                catch is CancellationError { throw CancellationError() }
                catch { try fm.removeItem(at: path) }
            }
        }
        if try importLegacy(asset, to: path) { progress(asset.size); return path }
        let received = ((try? fm.attributesOfItem(atPath: path.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let free = (try fm.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free > asset.size - received + 64 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        progress(received)
        try await transport.download(asset, to: path, progress: progress)
        try Task.checkCancellation()
        do { try UpdateFileIntegrity.verify(path, asset: asset) }
        catch is CancellationError { throw CancellationError() }
        catch { try? fm.removeItem(at: path); throw error }
        return path
    }

    private func importLegacy(_ asset: UpdateAsset, to destination: URL) throws -> Bool {
        let fm = FileManager.default
        let jobs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for job in jobs.prefix(100) {
            try Task.checkCancellation()
            let values = try job.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let source = job.appendingPathComponent(asset.name)
            do { try UpdateFileIntegrity.verify(source, asset: asset) }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
            try UpdateFileIntegrity.verify(destination, asset: asset)
            return true
        }
        return false
    }
}
