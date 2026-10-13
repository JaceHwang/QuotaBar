import Foundation
import XCTest
@testable import QuotaCore

final class UpdateFeedTests: XCTestCase {
    private func feed(_ version: String = "0.10.0", link: String = "https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.10.0", minOS: String = "14.0") -> Data {
        Data("""
        {"schemaVersion":1,"stable":{"macos-arm64":{"version":"\(version)","minOS":"\(minOS)","releaseNotesURL":"\(link)"},"windows-x64":{"version":"9.0.0","minOS":"10.0","releaseNotesURL":"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v9.0.0"}}}
        """.utf8)
    }
    func testEmbeddedNotesAndLegacyFeed() throws {
        var root = try JSONSerialization.jsonObject(with: feed()) as! [String: Any]
        var stable = root["stable"] as! [String: Any]
        var entry = stable["macos-arm64"] as! [String: Any]
        entry["summary"] = "Fix quota refresh"
        entry["releaseNotes"] = "Changes\n• Fix quota refresh"
        stable["macos-arm64"] = entry; root["stable"] = stable
        let data = try JSONSerialization.data(withJSONObject: root)
        let release = try UpdateFeed.available(in: data, platform: "macos-arm64", current: "0.9.0", os: "14.0")!
        XCTAssertEqual(release.summary, "Fix quota refresh")
        XCTAssertEqual(release.releaseNotes, "Changes\n• Fix quota refresh")
        XCTAssertEqual(release.notificationSummary, "Fix quota refresh")
        entry["summary"] = String(repeating: "😀", count: 300)
        entry["releaseNotes"] = String(repeating: "中", count: 17000)
        stable["macos-arm64"] = entry; root["stable"] = stable
        let bounded = try UpdateFeed.available(in: JSONSerialization.data(withJSONObject: root), platform: "macos-arm64", current: "0.9.0", os: "14.0")!
        XCTAssertEqual(bounded.summary?.count, 240)
        XCTAssertEqual(bounded.releaseNotes?.count, 16000)
        XCTAssertNil(try UpdateFeed.available(in: feed(), platform: "macos-arm64", current: "0.9.0", os: "14.0")?.summary)
        XCTAssertNotNil(try UpdateFeed.available(in: feed(), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
    }
    func testPlatformSelectionAndNumericVersionOrdering() throws {
        XCTAssertEqual(try UpdateFeed.available(in: feed(), platform: "macos-arm64", current: "0.9.0", os: "14.0")?.version, "0.10.0")
        XCTAssertNil(try UpdateFeed.available(in: feed(), platform: "macos-arm64", current: "0.10.0", os: "14.0"))
        XCTAssertNil(try UpdateFeed.available(in: feed(), platform: "macos-arm64", current: "1.0.0", os: "14.0"))
        XCTAssertNil(try UpdateFeed.available(in: feed(minOS: "15.0"), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
    }
    func testRejectsUnsafeLinksAndMalformedStableVersions() {
        for version in ["0.10.0-beta.1", "00.10.0", "a.b.c"] {
            XCTAssertThrowsError(try UpdateFeed.available(in: feed(version), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
        }
        for link in ["http://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.10.0", "https://evil.example/releases/tag/v0.10.0", "https://github.com/other/project/releases/tag/v0.10.0"] {
            XCTAssertThrowsError(try UpdateFeed.available(in: feed(link: link), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
        }
        XCTAssertThrowsError(try UpdateFeed.available(in: Data(repeating: 32, count: 262145), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
    }
    func testNotificationCompletionPreservesNewSnooze() {
        var policy = UpdateReminderPolicy()
        let submitted = policy
        let date = Date(timeIntervalSince1970: 10000)
        policy.snoozeUntil = date
        policy.recordNotification("0.10.0", attempted: submitted)
        XCTAssertEqual(policy.snoozeUntil, date)
        XCTAssertFalse(policy.shouldNotify("0.10.0", now: date.addingTimeInterval(-1)))
        let expired = policy
        policy.recordNotification("0.10.0", attempted: expired)
        XCTAssertNil(policy.snoozeUntil)
    }
    func testReminderSkipSnoozeAndDeduplicationPersist() throws {
        var policy = UpdateReminderPolicy()
        let now = Date(timeIntervalSince1970: 10000)
        XCTAssertTrue(policy.shouldNotify("0.10.0", now: now))
        policy.snoozeUntil = now.addingTimeInterval(86400)
        XCTAssertFalse(policy.shouldNotify("0.10.0", now: now))
        XCTAssertTrue(policy.shouldNotify("0.10.0", now: now.addingTimeInterval(86401)))
        policy.notifiedVersion = "0.10.0"
        policy.snoozeUntil = nil
        XCTAssertFalse(policy.shouldNotify("0.10.0", now: now))
        policy.skippedVersion = "0.11.0"
        let restored = try JSONDecoder().decode(UpdateReminderPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertFalse(restored.shouldNotify("0.11.0", now: now))
        XCTAssertTrue(restored.shouldNotify("0.12.0", now: now))
    }
}
