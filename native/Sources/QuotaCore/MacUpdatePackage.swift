import Foundation
import Darwin

public enum UpdatePackageError: Error, Equatable { case invalidJobTarget, expiredJob, consumedJob, invalidJobIdentity, invalidIdentity, linkedContent, invalidPackage, insufficientSpace, commandFailed, commandTimedOut }
public enum UpdateCommand {
    @discardableResult public static func run(_ executable: String, _ arguments: [String], working: URL, timeout: TimeInterval = 60, cancellable: Bool = true) throws -> Data {
        let fm = FileManager.default, output = working.appendingPathComponent("command-" + UUID().uuidString)
        guard fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UpdatePackageError.commandFailed }
        defer { try? fm.removeItem(at: output) }
        let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = writer; process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if cancellable { try Task.checkCancellation() }
                guard Date() < deadline else { throw UpdatePackageError.commandTimedOut }
                Thread.sleep(forTimeInterval: 0.05)
            }
            process.waitUntilExit()
        } catch {
            if process.isRunning { process.terminate(); let end = Date().addingTimeInterval(2); while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }; if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit() }
            throw error
        }
        guard process.terminationStatus == 0 else { throw UpdatePackageError.commandFailed }
        guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2 * 1024 * 1024 else { throw UpdatePackageError.invalidPackage }
        return try Data(contentsOf: output)
    }
}
public enum MacUpdatePackage {
    public static func treeBytes(_ root: URL) throws -> Int64 {
        let fm = FileManager.default; var pending = [root], count = 0, bytes: Int64 = 0
        while let path = pending.popLast() {
            try Task.checkCancellation(); count += 1
            let value = try path.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if value.isSymbolicLink == true { throw UpdatePackageError.linkedContent }
            guard count <= 20000 else { throw UpdatePackageError.invalidPackage }
            if value.isDirectory == true { pending.append(contentsOf: try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) }
            else {
                guard value.isRegularFile == true, let size = value.fileSize, size >= 0, Int64(size) <= 2 * 1024 * 1024 * 1024 - bytes else { throw UpdatePackageError.invalidPackage }
                bytes += Int64(size)
            }
        }
        return bytes
    }
    public static func verifyApp(_ app: URL, release: TrustedUpdateRelease, provenance: URL) throws {
        _ = try treeBytes(app)
        struct Info: Decodable { let CFBundleIdentifier: String; let CFBundleExecutable: String; let CFBundleShortVersionString: String; let LSMinimumSystemVersion: String; let CUSStandalone: Bool }
        let contents = app.appendingPathComponent("Contents")
        let info: Info
        do { info = try PropertyListDecoder().decode(Info.self, from: Data(contentsOf: contents.appendingPathComponent("Info.plist"))) }
        catch { throw UpdatePackageError.invalidIdentity }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard release.platform == "macos-arm64", info.CFBundleIdentifier == "com.jace.codex-quota", info.CFBundleExecutable == "CodexQuota", info.CFBundleShortVersionString == release.version, info.CUSStandalone,
              try !UpdateFeed.versionParts("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", os: true).lexicographicallyPrecedes(UpdateFeed.versionParts(info.LSMinimumSystemVersion, os: true)) else { throw UpdatePackageError.invalidIdentity }
        let data = try Data(contentsOf: provenance); try UpdateFileIntegrity.provenance(data, release: release)
        struct Proof: Decodable { let runtimeVersion: String; let applicationSignedSha256: String; let runtimeSignedSha256: String; let updaterSignedSha256: String; let sourceSnapshotSha256: String; let updateProtocol: Int }
        let proof = try JSONDecoder().decode(Proof.self, from: data)
        guard proof.runtimeVersion == "codex-cli 0.144.1", proof.updateProtocol == 1 else { throw UpdatePackageError.invalidPackage }
        for (path, hash) in [("MacOS/CodexQuota", proof.applicationSignedSha256), ("Helpers/codex", proof.runtimeSignedSha256), ("Helpers/QuotaBarUpdater", proof.updaterSignedSha256), ("Resources/SOURCE-SNAPSHOT.json", proof.sourceSnapshotSha256)] {
            guard TrustedUpdateRelease.hex(hash, count: 64), try UpdateFileIntegrity.sha256(contents.appendingPathComponent(path)) == hash else { throw UpdatePackageError.invalidPackage }
        }
        try UpdateCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], working: provenance.deletingLastPathComponent())
    }
    public static func prepare(_ download: DownloadedUpdate) throws -> URL {
        try UpdateFileIntegrity.verify(download.archive, asset: download.release.package)
        try UpdateFileIntegrity.verify(download.provenance, asset: download.release.provenance)
        let fm = FileManager.default, mount = download.directory.appendingPathComponent("mount-" + UUID().uuidString)
        try fm.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            try? UpdateCommand.run("/usr/bin/hdiutil", ["detach", mount.path], working: download.directory, timeout: 30, cancellable: false)
            try? fm.removeItem(at: mount)
        }
        try UpdateCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, "-plist", download.archive.path], working: download.directory)
        let incoming = mount.appendingPathComponent("QuotaBar.app")
        let bytes = try treeBytes(incoming)
        let free = (try fm.attributesOfFileSystem(forPath: download.directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= 2 * bytes + 64 * 1024 * 1024 else { throw UpdatePackageError.insufficientSpace }
        try verifyApp(incoming, release: download.release, provenance: download.provenance)
        try Task.checkCancellation()
        let candidate = download.directory.appendingPathComponent("QuotaBar.app")
        try UpdateCommand.run("/usr/bin/ditto", [incoming.path, candidate.path], working: download.directory)
        try verifyApp(candidate, release: download.release, provenance: download.provenance)
        try Task.checkCancellation(); return candidate
    }
}
