import Foundation
import XCTest
@testable import QuotaCore

final class TrustedUpdateReleaseTests: XCTestCase {
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
