import Foundation
import XCTest
@testable import QuotaCore
final class DynamicThresholdPolicyTests: XCTestCase {
    func testDynamicFieldsSurviveRoundTrip() throws {
        let json = #"{"schema":1,"enabledChannels":["bubble"],"rules":{"bankExpiring72h":["bubble"],"bankExpiring24h":["mobile"]},"lowRemainingThreshold":15,"lowRemainingThresholds":[30,20,10],"bankExpiryHours":[72,24,12],"bankThresholdChannels":{"72":["bubble"],"24":["mobile"],"12":[]}}"#
        let p = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: Data(json.utf8))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        XCTAssertEqual(encoded["lowRemainingThresholds"] as? [Int], [30,20,10])
        XCTAssertEqual(encoded["bankExpiryHours"] as? [Int], [72,24,12])
        XCTAssertNotNil(encoded["bankThresholdChannels"])
    }
    func testLegacyMixedChannelsAndColumnSelectionPreserveOthers() throws {
        var p = NotificationPolicyPreferences(); p.lowRemainingThreshold = 15
        p.rules[.bankExpiring72h] = [.bubble]; p.rules[.bankExpiring24h] = [.mobile]
        XCTAssertEqual(p.configuredLowThresholds, [15]); XCTAssertEqual(p.configuredBankHours, [72,24])
        XCTAssertNil(p.bankChannelSelected(.bubble)); XCTAssertNil(p.bankChannelSelected(.mobile))
        p.setBankHours([72,24,12]); XCTAssertEqual(p.bankChannels(for: 72), [.bubble]); XCTAssertEqual(p.bankChannels(for: 24), [.mobile]); XCTAssertEqual(p.bankChannels(for: 12), [])
        p.setBankHours([48,24,12], retainingChannelsFrom: [48:72]); XCTAssertEqual(p.bankChannels(for: 48), [.bubble])
        let oldMasters = p.enabledChannels, oldLow = p.rules[.quotaLow]
        p.selectColumn(.system)
        XCTAssertEqual(p.enabledChannels, oldMasters); XCTAssertEqual(p.configuredLowThresholds, [15])
        for category in NotificationCategory.allCases { XCTAssertTrue(p.rules[category]?.contains(.system) == true) }
        XCTAssertEqual(p.rules[.quotaLow]?.contains(.bubble), oldLow?.contains(.bubble))
        XCTAssertEqual(p.bankChannels(for: 24), [.mobile,.system]); XCTAssertEqual(p.bankChannels(for: 48), [.bubble,.system])
        XCTAssertTrue(p.bankChannelSelected(.system) == true)
        let decoded = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
    func testEmptyAndMalformedListsFailClosedAndSnapshotCannotExpand() throws {
        var p = NotificationPolicyPreferences.allSelected(); p.enabledChannels = Set(NotificationChannel.allCases)
        p.setLowThresholds([30,20,10]); p.setBankHours([72,24,12])
        XCTAssertEqual(NotificationPolicy.decision(category: .quotaLow, channel: .bubble, preferences: p, now: Date(), threshold: 20), .allowed)
        var snapshot = NotificationDeliverySnapshot(category: .bankExpiring72h, preferences: p, now: Date(), threshold: 12)
        p.setBankHours([72,24]); snapshot.restrict(to: p, now: Date())
        p.setBankHours([72,24,12]); XCTAssertFalse(snapshot.allows(.bubble, preferences: p, now: Date()))
        p.setLowThresholds([])
        XCTAssertEqual(NotificationPolicy.decision(category: .quotaLow, channel: .bubble, preferences: p, now: Date(), threshold: 20), .ruleOff)
        let malformed = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: Data(#"{"schema":1,"enabledChannels":["mobile"],"rules":{"bankExpiring72h":["mobile"]},"bankExpiryHours":"bad","lowRemainingThresholds":null}"#.utf8))
        XCTAssertEqual(malformed.configuredBankHours, []); XCTAssertEqual(malformed.configuredLowThresholds, [])
    }

    func testClearingBankHoursPreservesCurrentChannelsAcrossRoundTrip() throws {
        for dynamicMap in [false, true] {
            var p = NotificationPolicyPreferences.allSelected()
            p.rules[.bankExpiring72h] = dynamicMap ? [.mobile] : [.bubble]
            p.rules[.bankExpiring24h] = [.mobile]
            if dynamicMap { p.bankExpiryHours = [12]; p.bankThresholdChannels = [12: [.bubble]] }
            else { p.setBankHours([72]) }
            let masters = p.enabledChannels
            let otherRules = p.rules.filter { $0.key != .bankExpiring72h && $0.key != .bankExpiring24h }
            p.setBankHours([])
            XCTAssertEqual(p.bankChannelSelected(.bubble), true)
            XCTAssertEqual(p.bankChannelSelected(.mobile), false)
            p = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(p.configuredBankHours, [])
            XCTAssertEqual(p.bankThresholdChannels, [:])
            p.setBankHours([12])
            XCTAssertEqual(p.bankChannels(for: 12), [.bubble])
            XCTAssertEqual(p.enabledChannels, masters)
            XCTAssertEqual(p.rules.filter { $0.key != .bankExpiring72h && $0.key != .bankExpiring24h }, otherRules)
        }
    }

}
