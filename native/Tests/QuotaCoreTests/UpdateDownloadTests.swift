import Foundation
import CryptoKit
import XCTest
@testable import QuotaCore

private actor FixtureUpdateTransport: UpdateTransport {
    let release: Data, tag: Data, proof: Data
    let corrupt: Bool, late: Bool
    init(corrupt: Bool = false, late: Bool = false, wrongSource: Bool = false) throws {
        self.corrupt = corrupt; self.late = late
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/in-app-updates/release-cases.json").standardizedFileURL
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [[String: Any]]
        var r = rows[1]["release"] as! [String: Any]
        proof = try JSONSerialization.data(withJSONObject: ["kind": "release", "workingTreeDirty": false, "version": "2.0.0", "releaseTag": "v2.0.0", "sourceCommit": String(repeating: wrongSource ? "c" : "b", count: 40)])
        var assets = r["assets"] as! [[String: Any]]
        for index in [0, 1] {
            let bytes = index == 0 ? Data("package".utf8) : proof
            assets[index]["size"] = bytes.count
            assets[index]["digest"] = "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        r["assets"] = assets; release = try JSONSerialization.data(withJSONObject: r)
        tag = try JSONSerialization.data(withJSONObject: rows[1]["tag"]!)
    }
    func metadata(_ url: URL, limit: Int) async throws -> Data { url.path.contains("/releases/") ? release : tag }
    func download(_ asset: UpdateAsset, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let bytes = asset.name.hasSuffix(".dmg") ? Data((corrupt ? "corrupt" : "package").utf8) : proof
        try bytes.write(to: url); progress(Int64(bytes.count))
        if late { try? await Task.sleep(for: .milliseconds(50)) }
    }
}
final class UpdateDownloadTests: XCTestCase {
    func testTrustedDownloadVerifiesBytesAndProvenanceBeforeReturning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let client = UpdateDownloadClient(transport: try FixtureUpdateTransport())
        let value = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        XCTAssertEqual(try Data(contentsOf: value.archive), Data("package".utf8)); XCTAssertEqual(value.release.sourceCommit, String(repeating: "b", count: 40))
    }
    func testCorruptSourceAndLateCancellationCleanOnlyOwnedStage() async throws {
        for mode in 0..<3 {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let marker = root.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: marker)
            let client = UpdateDownloadClient(transport: try FixtureUpdateTransport(corrupt: mode == 0, late: mode == 2, wrongSource: mode == 1))
            let task = Task { try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root) }
            if mode == 2 { try await Task.sleep(for: .milliseconds(5)); task.cancel() }
            do { _ = try await task.value; XCTFail("Invalid download returned a package") } catch { }
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["keep.txt"])
        }
    }
}
