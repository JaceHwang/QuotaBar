import Foundation
import XCTest
@testable import QuotaCore

final class MacUpdatePackageTests: XCTestCase {
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
