import Foundation
import XCTest
@testable import QuotaCore
final class DynamicBankTests: XCTestCase {
    func testSharedDynamicBankCases() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("contracts/notifications/dynamic-bank-cases.json")
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [[String: Any]]
        let expiry = Date(timeIntervalSince1970: 1_900_000_000)
        for row in rows {
            var engine = QuotaExperienceEngine(state: ExperienceState(epoch: "a"))
            let thresholds = row["thresholds"] as! [Int], hours = row["hours"] as! [Int], stages = row["stages"] as! [Int]
            for i in hours.indices {
                let now = expiry.addingTimeInterval(Double(-hours[i]*3600))
                let credit = BankResetCredit(status: "available", grantedAt: nil, expiresAt: expiry, title: nil, description: nil, id: "one")
                let quota = AllowanceSnapshot(usedPercent: 0, remainingPercent: 100, resetsAt: expiry, receivedAt: now, bank: BankResetSummary(availableCount: 1, credits: [credit]))
                let observation = QuotaObservation(epoch: "a", sequence: i, receivedAt: now, quota: quota, bankFieldState: .value)
                let events = engine.observe(observation, now: now, bankThresholds: thresholds).bank
                XCTAssertEqual(events.first?.stage ?? 0, stages[i], row["name"] as! String)
                if !events.isEmpty {
                    XCTAssertTrue(engine.bankEventsAreCurrent(events, observation: observation, now: now, bankThresholds: thresholds))
                    XCTAssertFalse(engine.bankEventsAreCurrent(events, observation: observation, now: now, bankThresholds: []))
                }
                engine = QuotaExperienceEngine(state: try JSONDecoder().decode(ExperienceState.self, from: JSONEncoder().encode(engine.state)))
            }
        }
    }
    func testCustomBaselineWaitsForCompleteInventoryAndSurvivesRestart() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let credit = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(10*3600), title: nil, description: nil, id: "one")
        func observation(_ count: Int, _ sequence: Int) -> QuotaObservation {
            let quota = AllowanceSnapshot(usedPercent: 0, remainingPercent: 100, resetsAt: now, receivedAt: now, bank: BankResetSummary(availableCount: count, credits: [credit]))
            return QuotaObservation(epoch: "a", sequence: sequence, receivedAt: now, quota: quota, bankFieldState: .value)
        }
        var engine = QuotaExperienceEngine(state: ExperienceState(epoch: "a"))
        engine.suppressBankStages([12])
        XCTAssertTrue(engine.observe(observation(2, 0), now: now, bankThresholds: [72,24,12]).bank.isEmpty)
        XCTAssertTrue(engine.state.receipts.isEmpty)
        XCTAssertEqual(engine.state.pendingBankBaselines, [12])
        engine = QuotaExperienceEngine(state: try JSONDecoder().decode(ExperienceState.self, from: JSONEncoder().encode(engine.state)))
        XCTAssertTrue(engine.observe(observation(1, 1), now: now, bankThresholds: [72,24,12]).bank.isEmpty)
        XCTAssertNil(engine.state.pendingBankBaselines)
        XCTAssertEqual(engine.state.receipts.values.first?.stage, 12)
        XCTAssertTrue(engine.observe(observation(1, 2), now: now, bankThresholds: [72,24]).bank.isEmpty)
    }

    func testLongReceiptSurvivesThresholdRemoval() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let credit = BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(8760*3600), title: nil, description: nil, id: "long")
        let quota = AllowanceSnapshot(usedPercent: 0, remainingPercent: 100, resetsAt: now, receivedAt: now, bank: BankResetSummary(availableCount: 1, credits: [credit]))
        let observation = QuotaObservation(epoch: "a", sequence: 0, receivedAt: now, quota: quota, bankFieldState: .value)
        var engine = QuotaExperienceEngine(state: ExperienceState(epoch: "a"))
        XCTAssertEqual(engine.observe(observation, now: now, bankThresholds: [8760]).bank.first?.stage, 8760)
        _ = engine.observe(QuotaObservation(epoch: "a", sequence: 1, receivedAt: now, quota: quota, bankFieldState: .value), now: now, bankThresholds: [])
        XCTAssertEqual(engine.state.receipts.count, 1)
        XCTAssertTrue(engine.observe(QuotaObservation(epoch: "a", sequence: 2, receivedAt: now, quota: quota, bankFieldState: .value), now: now, bankThresholds: [8760]).bank.isEmpty)
    }

}
