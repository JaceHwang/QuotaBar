import Foundation
import XCTest
@testable import QuotaCore

final class NotificationPolicyTests: XCTestCase {
    func testCategoryChannelIndependenceAndPauseBoundary() {
        let now = Date(timeIntervalSince1970: 1800000000)
        for category in NotificationCategory.allCases {
            for channel in NotificationChannel.allCases {
                var p = NotificationPolicyPreferences()
                p.enabledChannels = Set(NotificationChannel.allCases)
                p.rules = [category: [channel]]
                for other in NotificationChannel.allCases {
                    XCTAssertEqual(NotificationPolicy.decision(category: category, channel: other, preferences: p, now: now), other == channel ? .allowed : .ruleOff)
                }
                p.bubblePausedUntil = now.addingTimeInterval(1)
                XCTAssertEqual(NotificationPolicy.decision(category: category, channel: channel, preferences: p, now: now), channel == .bubble ? .paused : .allowed)
                XCTAssertEqual(NotificationPolicy.decision(category: category, channel: channel, preferences: p, now: now.addingTimeInterval(1)), .allowed)
                p.enabledChannels = []
                XCTAssertEqual(NotificationPolicy.decision(category: category, channel: channel, preferences: p, now: now), .channelOff)
            }
        }
    }
    func testSharedMatrixFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/notifications/matrix-cases.json").standardizedFileURL
        let rows = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url))
        for row in rows {
            let category = try XCTUnwrap(NotificationCategory(rawValue: row["category"]!))
            let selected = try XCTUnwrap(NotificationChannel(rawValue: row["selected"]!))
            let channel = try XCTUnwrap(NotificationChannel(rawValue: row["channel"]!))
            var p = NotificationPolicyPreferences()
            p.enabledChannels = Set(NotificationChannel.allCases); p.rules = [category: [selected]]
            XCTAssertEqual(NotificationPolicy.decision(category: category, channel: channel, preferences: p, now: Date()).rawValue, row["expected"])
        }
    }
    func testEventCarriesCategoryWithoutChangingLegacyKind() {
        let m = ExperienceNotification(id: "low", kind: .recovery, epoch: "a", title: "x", body: "x", createdAt: Date(), category: .quotaLow)
        XCTAssertEqual(m.category, .quotaLow)
        XCTAssertEqual(m.priority, 1)
        XCTAssertEqual(m.kind, .recovery)
    }
    func testLegacyMigrationPreservesActualChannels() throws {
        struct Row: Decodable { let mode: NotificationDeliveryMode; let mobile: Bool; let recovery: Bool; let celebration: Bool; let bank: Bool; let updates: Bool; let channels: Set<NotificationChannel> }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/notifications/migration-cases.json").standardizedFileURL
        for row in try JSONDecoder().decode([Row].self, from: Data(contentsOf: url)) {
            let p = NotificationPolicyMigration.migrate(legacy: LegacyNotificationPreferences(mode: row.mode, recovery: row.recovery, celebration: row.celebration, bank: row.bank, updatesReminders: row.updates, barkEnabled: row.mobile))
            XCTAssertEqual(p.enabledChannels, row.channels)
            XCTAssertEqual(p.rules[.quotaRecovered], row.recovery || row.celebration ? row.channels : [])
            XCTAssertEqual(p.rules[.bankExpiring72h], row.bank ? row.channels : [])
            XCTAssertEqual(p.rules[.bankExpiring24h], row.bank ? row.channels : [])
            XCTAssertEqual(p.rules[.updateAvailable], row.updates ? row.channels : [])
            XCTAssertEqual(p.rules[.quotaLow], [])
            XCTAssertEqual(p.rules[.quotaExhausted], [])
        }
    }
    func testAtomicStoreMigratesOnceAndPreservesCorruptEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("policy.json")
        let store = NotificationPolicyStore(url: url)
        let old = LegacyNotificationPreferences(mode: .both, recovery: true, celebration: false, bank: true, updatesReminders: true, barkEnabled: true)
        let first = try store.loadOrMigrate(legacy: old)
        XCTAssertTrue(first.enabledChannels.contains(.mobile))
        let different = LegacyNotificationPreferences(mode: .off, recovery: false, celebration: false, bank: false, updatesReminders: false, barkEnabled: false)
        XCTAssertEqual(try store.loadOrMigrate(legacy: different), first)
        let bad = Data("broken".utf8); try bad.write(to: url)
        XCTAssertTrue(try store.loadOrMigrate(legacy: old).enabledChannels.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bad)
        try Data(#"{"schema":1,"enabledChannels":null,"rules":{}}"#.utf8).write(to: url)
        XCTAssertTrue(try store.loadOrMigrate(legacy: old).enabledChannels.isEmpty)
        XCTAssertTrue(store.corrupted)
        let blocker = root.appendingPathComponent("file"); try Data().write(to: blocker)
        XCTAssertThrowsError(try NotificationPolicyStore(url: blocker.appendingPathComponent("policy.json")).loadOrMigrate(legacy: old))
    }
    func testEligibilityOnlyShrinksAndReceiptsStayIndependent() {
        let now = Date()
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.bubble, .mobile]
        p.rules[.quotaRecovered] = [.bubble, .mobile]
        var snapshot = NotificationDeliverySnapshot(category: .quotaRecovered, preferences: p, now: now)
        XCTAssertTrue(snapshot.allows(.mobile, preferences: p, now: now))
        snapshot.recordAccepted(.bubble)
        XCTAssertTrue(snapshot.allows(.mobile, preferences: p, now: now))
        XCTAssertFalse(snapshot.allows(.bubble, preferences: p, now: now))
        p.enabledChannels = [.bubble]; snapshot.restrict(to: p, now: now)
        p.enabledChannels.insert(.mobile)
        XCTAssertFalse(snapshot.allows(.mobile, preferences: p, now: now))
        p.enabledChannels.insert(.system); p.rules[.quotaRecovered]?.insert(.system)
        XCTAssertFalse(snapshot.allows(.system, preferences: p, now: now))
    }
    func testCategoryPriorityDrivesActualQueues() {
        let date = Date()
        var queue = ExperienceNotificationQueue()
        var state = NotificationPresentationState()
        for category in [NotificationCategory.updateAvailable, .quotaLow, .quotaExhausted] {
            let m = ExperienceNotification(id: category.rawValue, kind: .recovery, epoch: "a", title: "x", body: "", createdAt: date, category: category)
            queue.enqueue(m); state.enqueue(m, canPresent: true, now: date)
        }
        XCTAssertEqual(queue.next(now: date)?.category, .quotaExhausted)
        XCTAssertEqual(state.next(canPresent: true, now: date)?.category, .quotaExhausted)
    }
    func testDefaultsAndSafeDecoding() throws {
        let p = NotificationPolicyPreferences()
        XCTAssertEqual(p.rules[.quotaRecovered], [.bubble])
        XCTAssertEqual(p.rules[.bankExpiring24h], [.bubble])
        XCTAssertEqual(p.rules[.updateAvailable], [])
        XCTAssertEqual(p.rules[.quotaLow], [])
        XCTAssertEqual(p.lowRemainingThreshold, 20)
        let bad = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: Data(#"{"schema":99,"enabledChannels":["mobile"]}"#.utf8))
        XCTAssertTrue(bad.enabledChannels.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(NotificationPolicyPreferences.self, from: JSONEncoder().encode(p)), p)
    }
}
