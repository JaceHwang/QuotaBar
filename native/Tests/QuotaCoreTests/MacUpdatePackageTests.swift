import Foundation
import XCTest
@testable import QuotaCore

final class MacUpdatePackageTests: XCTestCase {
    func testSignedReadOnlyDMGIsMountedVerifiedCopiedAndDetached() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), app = source.appendingPathComponent("QuotaBar.app"), contents = app.appendingPathComponent("Contents")
        for name in ["MacOS", "Helpers", "Resources"] { try fm.createDirectory(at: contents.appendingPathComponent(name), withIntermediateDirectories: true) }
        let c = root.appendingPathComponent("fixture.c"), binary = root.appendingPathComponent("fixture")
        try Data("int main(){return 0;}".utf8).write(to: c)
        try UpdateCommand.run("/usr/bin/xcrun", ["clang", c.path, "-o", binary.path], working: root)
        for name in ["MacOS/CodexQuota", "Helpers/codex", "Helpers/QuotaBarUpdater"] { try fm.copyItem(at: binary, to: contents.appendingPathComponent(name)) }
        try Data("{}".utf8).write(to: contents.appendingPathComponent("Resources/SOURCE-SNAPSHOT.json"))
        let plist: [String: Any] = ["CFBundleIdentifier": "com.jace.codex-quota", "CFBundleExecutable": "CodexQuota", "CFBundleShortVersionString": "2.0.0", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0", "CUSStandalone": true]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        for path in [contents.appendingPathComponent("Helpers/codex"), contents.appendingPathComponent("Helpers/QuotaBarUpdater"), app] { try UpdateCommand.run("/usr/bin/codesign", ["--force", "--sign", "-", path.path], working: root) }
        let proof = root.appendingPathComponent("proof.json")
        let value: [String: Any] = ["kind": "release", "workingTreeDirty": false, "version": "2.0.0", "releaseTag": "v2.0.0", "sourceCommit": String(repeating: "b", count: 40), "runtimeVersion": "codex-cli 0.144.1", "updateProtocol": 1,
            "applicationSignedSha256": try UpdateFileIntegrity.sha256(contents.appendingPathComponent("MacOS/CodexQuota")), "runtimeSignedSha256": try UpdateFileIntegrity.sha256(contents.appendingPathComponent("Helpers/codex")), "updaterSignedSha256": try UpdateFileIntegrity.sha256(contents.appendingPathComponent("Helpers/QuotaBarUpdater")), "sourceSnapshotSha256": try UpdateFileIntegrity.sha256(contents.appendingPathComponent("Resources/SOURCE-SNAPSHOT.json"))]
        try JSONSerialization.data(withJSONObject: value).write(to: proof)
        let archive = root.appendingPathComponent("fixture.dmg")
        try UpdateCommand.run("/usr/bin/hdiutil", ["create", "-quiet", "-volname", "QuotaBar test", "-srcfolder", source.path, "-format", "UDZO", archive.path], working: root)
        func asset(_ path: URL) throws -> UpdateAsset { UpdateAsset(name: path.lastPathComponent, url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/" + path.lastPathComponent)!, size: Int64(try path.resourceValues(forKeys: [.fileSizeKey]).fileSize!), sha256: try UpdateFileIntegrity.sha256(path)) }
        let release = try TrustedUpdateRelease(version: "2.0.0", platform: "macos-arm64", sourceCommit: String(repeating: "b", count: 40), package: asset(archive), provenance: asset(proof))
        let prepared = try MacUpdatePackage.prepare(DownloadedUpdate(release: release, directory: root, archive: archive, provenance: proof))
        XCTAssertEqual(prepared.lastPathComponent, "QuotaBar.app")
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("mount-") })
        try MacUpdatePackage.verifyApp(prepared, release: release, provenance: proof)
    }
    func testLinkedAndWrongIdentityAppsAreRejectedBeforeInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("QuotaBar.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let proof = root.appendingPathComponent("proof.json"); try Data("{}".utf8).write(to: proof)
        let asset = UpdateAsset(name: "example", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/example")!, size: 2, sha256: String(repeating: "a", count: 64))
        let release = TrustedUpdateRelease(version: "2.0.0", platform: "macos-arm64", sourceCommit: String(repeating: "b", count: 40), package: asset, provenance: asset)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "evil.app", "CFBundleShortVersionString": "2.0.0"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try MacUpdatePackage.verifyApp(app, release: release, provenance: proof)) { XCTAssertEqual($0 as? UpdatePackageError, .invalidIdentity) }
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/linked"), withDestinationURL: root)
        XCTAssertThrowsError(try MacUpdatePackage.verifyApp(app, release: release, provenance: proof)) { XCTAssertEqual($0 as? UpdatePackageError, .linkedContent) }
    }
}
