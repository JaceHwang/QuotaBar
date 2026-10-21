import Foundation
import XCTest
@testable import QuotaCore

final class QuotaExperienceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func quota(_ used: Double, reset: Double = 1000, bank: BankResetSummary? = nil) -> AllowanceSnapshot {
        AllowanceSnapshot(usedPercent: used, remainingPercent: Int((100-used).rounded()), resetsAt: now.addingTimeInterval(reset), receivedAt: now, windowDurationMins: 300, planType: "plus", bank: bank)
    }
    func testDefaultsAndRawBankMetadata() throws {
        XCTAssertEqual(QuotaExperiencePreferences(), QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: false))
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
            engine.configure(QuotaExperiencePreferences(recovery: true))
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
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(bank: true))
        XCTAssertEqual(e.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .omitted), now: now).bank.count, 0)
        let o = QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota(0, bank: bank), bankFieldState: .value)
        XCTAssertEqual(e.observe(o, now: now).bank.first?.stage, 72)
        var restored = QuotaExperienceEngine(state: e.state); restored.configure(QuotaExperiencePreferences(bank: true))
        XCTAssertTrue(restored.observe(o, now: now).bank.isEmpty)
        let later = now.addingTimeInterval(48*3600)
        XCTAssertEqual(restored.observe(QuotaObservation(epoch: "a", sequence: 3, receivedAt: later, quota: quota(0, bank: bank), bankFieldState: .value), now: later).bank.first?.stage, 24)
    }
    func testBankQueuedMessageRejectsReplacedInventory() {
        let c = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil, id: "old")
        let b = BankResetSummary(availableCount: 1, credits: [c])
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(bank: true))
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
            var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(recovery: true))
            _ = e.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(80)), now: now)
            var q = quota(0, reset: 2000)
            if variant == 0 { e.configure(QuotaExperiencePreferences()); e.configure(QuotaExperiencePreferences(recovery: true)) }
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
        var e = QuotaExperienceEngine(state: ExperienceState(epoch: "a")); e.configure(QuotaExperiencePreferences(bank: true))
        let o = QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota(0, bank: b), bankFieldState: .value)
        let events = e.observe(o, now: now).bank
        XCTAssertEqual(events.count, 1); XCTAssertEqual(events.first?.stage, 24); XCTAssertEqual(events.first?.count, 2)
        XCTAssertTrue(e.observe(QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: o.quota, bankFieldState: .value), now: now).bank.isEmpty)
    }

}
