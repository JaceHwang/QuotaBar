import Foundation
import XCTest
@testable import QuotaCore

final class TrustedUpdateReleaseTests: XCTestCase {
    func testBetaReleaseRequiresExplicitPermissionAndMatchingGithubFlag() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/in-app-updates/release-cases.json").standardizedFileURL
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        let row = rows[1]
        var release = row["release"] as! [String: Any]; release["prerelease"] = true
        let json = String(data: try JSONSerialization.data(withJSONObject: release), encoding: .utf8)!.replacingOccurrences(of: "2.0.0", with: "2.0.0-beta.1")
        let bytes = Data(json.utf8), tag = try JSONSerialization.data(withJSONObject: row["tag"]!)
        XCTAssertThrowsError(try TrustedUpdateRelease.parse(releaseJSON: bytes, tagJSON: tag, version: "2.0.0-beta.1", platform: "macos-arm64", currentVersion: "1.9.0"))
        let valid = try TrustedUpdateRelease.parse(releaseJSON: bytes, tagJSON: tag, version: "2.0.0-beta.1", platform: "macos-arm64", currentVersion: "1.9.0", allowBeta: true)
        XCTAssertEqual(valid.version, "2.0.0-beta.1")
        let wrongFlag = Data(json.replacingOccurrences(of: "\"prerelease\":true", with: "\"prerelease\":false").utf8)
        XCTAssertThrowsError(try TrustedUpdateRelease.parse(releaseJSON: wrongFlag, tagJSON: tag, version: "2.0.0-beta.1", platform: "macos-arm64", currentVersion: "1.9.0", allowBeta: true))
    }
    func testSharedOfficialReleaseCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/in-app-updates/release-cases.json").standardizedFileURL
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for row in cases {
            let release = try JSONSerialization.data(withJSONObject: row["release"]!), tag = try JSONSerialization.data(withJSONObject: row["tag"]!)
            do {
                let result = try TrustedUpdateRelease.parse(releaseJSON: release, tagJSON: tag, version: row["version"] as! String, platform: row["platform"] as! String, currentVersion: row["current"] as! String)
                XCTAssertEqual(row["valid"] as? Bool, true, row["name"] as! String)
                XCTAssertEqual(result.sourceCommit, String(repeating: "b", count: 40))
                XCTAssertEqual(result.package.size, 1024)
            } catch { XCTAssertEqual(row["valid"] as? Bool, false, row["name"] as! String) }
        }
    }
    func testRedirectPolicyRejectsLocalHostsAndNonHTTPS() {
        for text in ["http://github.com/x", "https://127.0.0.1/x", "https://github.com.evil/x", "https://github.com:444/x", "https://user@github.com/x", "https://github.com/x#x"] {
            XCTAssertFalse(TrustedUpdateRelease.allowedDownloadRedirect(URL(string: text)!))
        }
        XCTAssertTrue(TrustedUpdateRelease.allowedDownloadRedirect(URL(string: "https://release-assets.githubusercontent.com/a?sig=example")!))
    }
}
