import Foundation
import XCTest
@testable import QuotaCore

final class UpdateFeedTests: XCTestCase {
    private func feed(_ version: String = "0.10.0", link: String = "https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.10.0", minOS: String = "14.0") -> Data {
        Data("""
        {"schemaVersion":1,"stable":{"macos-arm64":{"version":"\(version)","minOS":"\(minOS)","releaseNotesURL":"\(link)"},"windows-x64":{"version":"9.0.0","minOS":"10.0","releaseNotesURL":"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v9.0.0"}}}
        """.utf8)
    }
    func testStableReleaseUpgradesInstalledBetaOfSameNumericVersion() throws {
        let release = try UpdateFeed.available(in: feed("1.7.0", link: "https://github.com/JaceHwang/QuotaBar/releases/tag/v1.7.0"), platform: "macos-arm64", current: "1.7.0-beta.11", os: "14.0")
        XCTAssertEqual(release?.version, "1.7.0")
    }
    func testBetaOptInChoosesNewestPermittedReleaseAndIsolatesMalformedBeta() throws {
        let json = """
        {"schemaVersion":1,"stable":{"macos-arm64":{"version":"1.7.0","minOS":"14.0","releaseNotesURL":"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.7.0"}},"beta":{"macos-arm64":{"version":"1.8.0-beta.11","minOS":"14.0","releaseNotesURL":"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.8.0-beta.11"}}}
        """
        let data = Data(json.utf8)
        let off = try UpdateFeed.select(in: data, platform: "macos-arm64", current: "1.6.0", os: "14.0", allowBeta: false)
        XCTAssertEqual(off.release?.version, "1.7.0"); XCTAssertFalse(off.betaError)
        let on = try UpdateFeed.select(in: data, platform: "macos-arm64", current: "1.8.0-beta.2", os: "14.0", allowBeta: true)
        XCTAssertEqual(on.release?.version, "1.8.0-beta.11"); XCTAssertFalse(on.betaError)
        let invalid = Data(json.replacingOccurrences(of: "\"beta\":{\"macos-arm64\":{", with: "\"beta\":{\"macos-arm64\":{\"bad\":true,").replacingOccurrences(of: "1.8.0-beta.11", with: "1.8.0-beta.0").utf8)
        let fallback = try UpdateFeed.select(in: invalid, platform: "macos-arm64", current: "1.6.0", os: "14.0", allowBeta: true)
        XCTAssertEqual(fallback.release?.version, "1.7.0"); XCTAssertTrue(fallback.betaError)
        XCTAssertFalse(try UpdateFeed.select(in: invalid, platform: "macos-arm64", current: "1.6.0", os: "14.0", allowBeta: false).betaError)
    }
    func testProductVersionBoundsAndPrecedence() throws {
        XCTAssertLessThan(try ProductVersion("1.7.0-beta.2"), try ProductVersion("1.7.0-beta.11"))
        XCTAssertLessThan(try ProductVersion("1.7.0-beta.11"), try ProductVersion("1.7.0"))
        for invalid in ["1.0.0-beta.0", "1.0.0-beta.01", "65535.0.0", "1.0.0-rc.1", "1.0.0-beta.2147483648", "1.0.0+meta"] {
            XCTAssertThrowsError(try ProductVersion(invalid), invalid)
        }
    }
    func testBetaConsentDefaultsOffPersistsAndQuarantinesCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("update-channel.json"), unrelated = root.appendingPathComponent("preferences.json")
        try Data("keep".utf8).write(to: unrelated)
        let store = UpdateChannelStore(url: file)
        XCTAssertFalse(store.load())
        try store.save(enabled: true)
        XCTAssertTrue(UpdateChannelStore(url: file).load())
        try Data("{\"schema\":1,\"betaEnabled\":\"yes\"}".utf8).write(to: file)
        XCTAssertFalse(store.load())
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("update-channel.json.corrupt-") })
        try Data("{\"schema\":1,\"betaEnabled\":true,\"betaEnabled\":false}".utf8).write(to: file)
        XCTAssertFalse(store.load(), "Ambiguous duplicate consent must fail closed")
        let blocked = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        XCTAssertThrowsError(try UpdateChannelStore(url: blocked.appendingPathComponent("channel.json")).save(enabled: true))
    }
    func testFullVersionIdentityCannotTreatBetaAsLegacyStable() throws {
        func proof(_ version: String) -> Data { Data("{\"kind\":\"release\",\"workingTreeDirty\":false,\"version\":\"\(version)\",\"releaseTag\":\"v\(version)\",\"sourceCommit\":\"\(String(repeating: "b", count: 40))\"}".utf8) }
        XCTAssertEqual(try ProductIdentity.resolve(numeric: "1.8.0", full: "1.8.0-beta.1", provenance: proof("1.8.0-beta.1")).version, "1.8.0-beta.1")
        XCTAssertEqual(try ProductIdentity.resolve(numeric: "1.8.0", full: nil, provenance: proof("1.8.0")).version, "1.8.0")
        XCTAssertThrowsError(try ProductIdentity.resolve(numeric: "1.8.0", full: nil, provenance: proof("1.8.0-beta.1")))
        XCTAssertThrowsError(try ProductIdentity.resolve(numeric: "1.8.0", full: "1.8.0-beta.2", provenance: proof("1.8.0-beta.1")))
        XCTAssertThrowsError(try ProductIdentity.resolve(numeric: "1.8.0", full: nil, provenance: Data("{}".utf8)))
        XCTAssertThrowsError(try ProductIdentity.resolve(numeric: "1.8.0", full: "1.8.0-beta.1", provenance: Data("{\"kind\":\"release\",\"workingTreeDirty\":false,\"version\":\"1.8.0-beta.1\",\"releaseTag\":\"v1.8.0-beta.1\"}".utf8)))
        let candidate = Data("{\"kind\":\"local-development-candidate\",\"workingTreeDirty\":true,\"version\":\"1.8.0-beta.1\",\"releaseTag\":null}".utf8)
        let identity = try ProductIdentity.resolve(numeric: "1.8.0", full: "1.8.0-beta.1", provenance: candidate)
        XCTAssertTrue(identity.development); XCTAssertEqual(identity.version, "1.8.0-beta.1")
        XCTAssertThrowsError(try ProductIdentity.resolve(numeric: "1.8.0", full: nil, provenance: Data("{\"kind\":\"local-development-candidate\",\"workingTreeDirty\":true}".utf8)))
    }
    func testRenamedRepositoryUsesCanonicalEndpointAndAcceptsCanonicalRelease() throws {
        XCTAssertEqual(UpdateFeed.endpoint.absoluteString, "https://jacehwang.github.io/QuotaBar/updates.json")
        let data = feed(link: "https://github.com/JaceHwang/QuotaBar/releases/tag/v0.10.0")
        XCTAssertEqual(try UpdateFeed.available(in: data, platform: "macos-arm64", current: "0.9.0", os: "14.0")?.version, "0.10.0")
        XCTAssertThrowsError(try UpdateFeed.available(in: feed(link: "https://github.com/JaceHwang/QuotaBar-evil/releases/tag/v0.10.0"), platform: "macos-arm64", current: "0.9.0", os: "14.0"))
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
    func testOtherPlatformMalformedEntryDoesNotHideValidMacUpdate() throws {
        let json = """
        {"schemaVersion":1,"stable":{"macos-arm64":{"version":"1.7.0","minOS":"14.0","releaseNotesURL":"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.7.0"},"windows-x64":{"version":false}}}
        """
        XCTAssertEqual(try UpdateFeed.available(in: Data(json.utf8), platform: "macos-arm64", current: "1.6.0", os: "14.0")?.version, "1.7.0")
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
