import Foundation
import XCTest
@testable import QuotaCore

final class QuotaExperienceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func quota(_ used: Double, reset: Double = 1000, bank: BankResetSummary? = nil) -> AllowanceSnapshot {
        AllowanceSnapshot(usedPercent: used, remainingPercent: Int((100-used).rounded()), resetsAt: now.addingTimeInterval(reset), receivedAt: now, windowDurationMins: 300, planType: "plus", bank: bank)
    }
    func testCelebrationAlsoRequestsSingleRecoveryNotification() {
        XCTAssertTrue(QuotaExperiencePreferences(moods: false, recovery: false, celebration: true, bank: false).recoveryNotificationEnabled)
        XCTAssertTrue(QuotaExperiencePreferences().recoveryNotificationEnabled)
        XCTAssertFalse(QuotaExperiencePreferences(moods: true, recovery: false, celebration: false, bank: true).recoveryNotificationEnabled)
    }
    func testPendingBankBaselineSurvivesRestart() throws {
        let bank = BankResetSummary(availableCount: 1, credits: [BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil, id: "old")])
        var engine = QuotaExperienceEngine(state: ExperienceState(epoch: "a"))
        engine.suppressBankStages([24])
        let state = try JSONDecoder().decode(ExperienceState.self, from: JSONEncoder().encode(engine.state))
        var restarted = QuotaExperienceEngine(state: state)
        let summary = BankResetSummary(availableCount: 1, credits: nil)
        XCTAssertTrue(restarted.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: summary), bankFieldState: .value), now: now).bank.isEmpty)
        XCTAssertEqual(restarted.state.pendingBankBaselines, [24])
        let invalid = BankResetSummary(availableCount: 1, credits: [bank.credits![0], BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil, id: "other")])
        _ = restarted.observe(QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota(0, bank: invalid), bankFieldState: .value), now: now)
        XCTAssertEqual(restarted.state.pendingBankBaselines, [24])
        XCTAssertTrue(restarted.observe(QuotaObservation(epoch: "a", sequence: 3, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .value), now: now).bank.isEmpty)
        XCTAssertTrue(restarted.observe(QuotaObservation(epoch: "a", sequence: 4, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .value), now: now).bank.isEmpty)
    }
    func testDefaultsAndRawBankMetadata() throws {
        XCTAssertEqual(QuotaExperiencePreferences(), QuotaExperiencePreferences(moods: true, recovery: true, celebration: true, bank: true))
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(QuotaExperiencePreferences.self, from: Data("{}".utf8)), QuotaExperiencePreferences())
        let partial = try decoder.decode(QuotaExperiencePreferences.self, from: Data(#"{"moods":false}"#.utf8))
        XCTAssertEqual(partial, QuotaExperiencePreferences(moods: false))
        let disabled = QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: false)
        XCTAssertEqual(try decoder.decode(QuotaExperiencePreferences.self, from: JSONEncoder().encode(disabled)), disabled)
        let data = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":5,"resetsAt":1800001000}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"credit1","resetType":"codex","status":"available","expiresAt":1800086400}]}}}"#.utf8)
        let observation = try QuotaObservation.decode(data, epoch: "a", sequence: 1, receivedAt: now)
        XCTAssertEqual(observation.bankFieldState, .value)
        XCTAssertEqual(observation.quota.bank?.credits?.first?.id, "credit1")
        XCTAssertEqual(observation.quota.bank?.credits?.first?.resetType, "codex")
    }
    func testSharedRecoverySequences() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("contracts/experience/recovery-sequences.json")
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [[String: Any]]
        for row in rows {
            var engine = QuotaExperienceEngine(state: ExperienceState(epoch: "a"))
            engine.configure(QuotaExperiencePreferences(moods: false, recovery: true, celebration: false, bank: false))
            let used = row["used"] as! [Double], resets = row["reset"] as! [Double], seconds = row["seconds"] as! [Double], events = row["events"] as! [Int]
            for i in used.indices {
                let at = now.addingTimeInterval(seconds[i])
                let o = QuotaObservation(epoch: "a", sequence: i+1, receivedAt: at, quota: quota(used[i], reset: resets[i]))
                XCTAssertEqual(engine.observe(o, now: at).recoveries.count, events[i], row["name"] as! String)
            }
        }
    }
    func testMoodUsesRawPercentageAndFreshness() {
        XCTAssertEqual(QuotaMood.resolve(quota(99.6), ready: true, now: now), .low)
        XCTAssertEqual(QuotaMood.resolve(quota(80), ready: true, now: now), .low)
        XCTAssertEqual(QuotaMood.resolve(quota(100), ready: true, now: now), .exhausted)
        XCTAssertEqual(QuotaMood.resolve(quota(0), ready: true, now: now.addingTimeInterval(121)), .unavailable)
    }
    func testBankStagesPersistAndDoNotUseMissingData() {
        let credit = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(72*3600), title: nil, description: nil, id: "one")
        let bank = BankResetSummary(availableCount: 1, credits: [credit])
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        XCTAssertEqual(e.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .omitted), now: now).bank.count, 0)
        let o = QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .value)
        XCTAssertEqual(e.observe(o, now: now).bank.first?.stage, 72)
        var restored = QuotaExperienceEngine(state: e.state); restored.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        XCTAssertTrue(restored.observe(o, now: now).bank.isEmpty)
        let later = now.addingTimeInterval(48*3600)
        XCTAssertEqual(restored.observe(QuotaObservation(epoch: "a", sequence: 3, receivedAt: later, quota: quota(0, bank: bank), bankFieldState: .value), now: later).bank.first?.stage, 24)
    }
    func testBankQueuedMessageRejectsReplacedInventory() {
        let c = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil, id: "old")
        let b = BankResetSummary(availableCount: 1, credits: [c])
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        let o = QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: b), bankFieldState: .value)
        let events = e.observe(o, now: now).bank
        XCTAssertTrue(e.bankEventsAreCurrent(events, observation: o, now: now))
        let changed = BankResetCredit(status: "available", grantedAt: nil, expiresAt: c.expiresAt, title: nil, description: nil, id: "different")
        XCTAssertFalse(e.bankEventsAreCurrent(events, observation: QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota(0, bank: BankResetSummary(availableCount: 1, credits: [changed])), bankFieldState: .value), now: now))
    }
    func testPartialBankDetailsAreExplicit() {
        let q = quota(0, bank: BankResetSummary(availableCount: 2, credits: []))
        let content = QuotaDetailFormatter().content(snapshot: q, now: now, language: .simplifiedChinese, timeZone: .current)
        XCTAssertTrue(content.rows.contains { $0.value == "部分权益未提供到期时间" })
    }

    func testAuthenticationPlanDurationAndEnableChangesDoNotRestore() {
        for variant in 0..<5 {
            var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: true, celebration: false, bank: false))
            _ = e.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(80)), now: now)
            var q = quota(0, reset: 2000)
            if variant == 0 { e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: false)); e.configure(QuotaExperiencePreferences(moods: false, recovery: true, celebration: false, bank: false)) }
            if variant == 1 { q = AllowanceSnapshot(usedPercent: 0, remainingPercent: 100, resetsAt: now.addingTimeInterval(2000), receivedAt: now, windowDurationMins: 300, planType: "pro") }
            if variant == 2 { q = AllowanceSnapshot(usedPercent: 0, remainingPercent: 100, resetsAt: now.addingTimeInterval(2000), receivedAt: now, windowDurationMins: 600, planType: "plus") }
            for index in 2...3 {
                let at = now.addingTimeInterval(Double(index)*60)
                let o = QuotaObservation(epoch: variant == 3 ? "different" : "a", sequence: index, receivedAt: at, quota: q, source: variant == 4 ? .notification : .fullRead)
                XCTAssertTrue(e.observe(o, now: at).recoveries.isEmpty)
            }
        }
    }
    func testFirstLateBankOnlyEmits24AndUnknownDatesDoNotInventEvents() {
        let c = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(10*3600), title: nil, description: nil)
        let b = BankResetSummary(availableCount: 3, credits: [c, c, BankResetCredit(status: "available", grantedAt: nil, expiresAt: nil, title: nil, description: nil)])
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        let o = QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: b), bankFieldState: .value)
        let events = e.observe(o, now: now).bank
        XCTAssertEqual(events.count, 1); XCTAssertEqual(events.first?.stage, 24); XCTAssertEqual(events.first?.count, 2)
        XCTAssertTrue(e.observe(QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: o.quota, bankFieldState: .value), now: now).bank.isEmpty)
    }

    func testQueuedBankRejectsReducedAvailableCount() {
        let c = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil)
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        let q = quota(0, bank: BankResetSummary(availableCount: 2, credits: [c,c]))
        let o = QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: q, bankFieldState: .value)
        let events = e.observe(o, now: now).bank
        let changed = QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota(0, bank: BankResetSummary(availableCount: 1, credits: [c,c])), bankFieldState: .value)
        XCTAssertFalse(e.bankEventsAreCurrent(events, observation: changed, now: now))
    }
    func testMissingPlanOrWindowLengthNeverCertifiesRecovery() {
        for variant in 0..<3 {
            var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(moods: false, recovery: true, celebration: false, bank: false))
            for i in 0..<3 {
                let used = i == 0 ? 100.0 : 0.0
                let at = now.addingTimeInterval(Double(i)*60)
                let primary = QuotaWindowSnapshot(usedPercent: used, remainingPercent: Int(100-used), resetsAt: now.addingTimeInterval(1000), windowDurationMins: variant == 1 ? nil : 300)
                let secondary = variant == 2 ? QuotaWindowSnapshot(usedPercent: used, remainingPercent: Int(100-used), resetsAt: now.addingTimeInterval(2000), windowDurationMins: nil) : nil
                let q = AllowanceSnapshot(primary: primary, secondary: secondary, receivedAt: at, planType: variant == 0 ? nil : "plus")
                XCTAssertTrue(e.observe(QuotaObservation(epoch: "a", sequence: i+1, receivedAt: at, quota: q), now: at).recoveries.isEmpty)
            }
        }
    }

    func testCorruptStoreWaitsForKnownBankDetailsBeforeSuppressingBaseline() {
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a"), suppressFirstBank: true); e.configure(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: true))
        let unknown = quota(0, bank: BankResetSummary(availableCount: 1, credits: nil))
        _ = e.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: unknown, bankFieldState: .value), now: now)
        let c = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil)
        let known = quota(0, bank: BankResetSummary(availableCount: 1, credits: [c]))
        XCTAssertTrue(e.observe(QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: known, bankFieldState: .value), now: now).bank.isEmpty)
    }

}
