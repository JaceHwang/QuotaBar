import Foundation
import XCTest
@testable import QuotaCore
final class QuotaWarningTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1800000000)
    func observation(_ remaining: Int, _ sequence: Int, reset: Double = 3600, second: Int? = nil, epoch: String = "a", age: Double = 0, time: Double? = nil, used: Double? = nil) -> QuotaObservation {
        let at = now.addingTimeInterval((time ?? Double(sequence)*20)-age)
        let q = AllowanceSnapshot(usedPercent: used ?? Double(100-remaining), remainingPercent: remaining, resetsAt: now.addingTimeInterval(reset), receivedAt: at, windowDurationMins: 300, planType: "plus", secondary: second.map { QuotaWindowSnapshot(usedPercent: Double(100-$0), remainingPercent: $0, resetsAt: now.addingTimeInterval(604800), windowDurationMins: 10080) })
        return QuotaObservation(epoch: epoch, sequence: sequence, receivedAt: at, quota: q)
    }
    func observe(_ engine: inout QuotaWarningEngine, _ remaining: Int, _ sequence: Int, reset: Double = 3600, second: Int? = nil, threshold: Int = 20) -> [QuotaWarningEvent] {
        engine.observe(observation(remaining, sequence, reset: reset, second: second), threshold: threshold, now: now.addingTimeInterval(Double(sequence)*20))
    }
    func testDynamicSharedWarningCases() throws {
        struct Step: Decodable { let remaining: Int; let second: Int?; let thresholds: [Int]; let legacy: Bool?; let restart: Bool?; let configure: [[Int]]?; let stale: Bool?; let expected: [Int]; let periods: [String]? }
        struct Case: Decodable { let name: String; let steps: [Step] }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/notifications/dynamic-warning-cases.json").standardizedFileURL
        for item in try JSONDecoder().decode([Case].self, from: Data(contentsOf: url)) {
            var engine = QuotaWarningEngine()
            for (i, step) in item.steps.enumerated() {
                if step.legacy == true {
                    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state)) as! [String: Any]
                    json.removeValue(forKey: "thresholds")
                    var periods = json["periods"] as! [String: [String: Any]]
                    for key in Array(periods.keys) { periods[key]?.removeValue(forKey: "consumedThresholds") }
                    json["periods"] = periods
                    engine = QuotaWarningEngine(state: try JSONDecoder().decode(QuotaWarningState.self, from: JSONSerialization.data(withJSONObject: json)))
                }
                if step.restart == true { engine = QuotaWarningEngine(state: try JSONDecoder().decode(QuotaWarningState.self, from: JSONEncoder().encode(engine.state))) }
                for levels in step.configure ?? [] { engine.configureLowThresholds(levels) }
                let events = engine.observe(observation(step.remaining, i+1, second: step.second, age: step.stale == true ? 121 : 0), thresholds: step.thresholds, now: now.addingTimeInterval(Double(i+1)*20))
                XCTAssertEqual(events.map { $0.category == .quotaExhausted ? 0 : $0.threshold }, step.expected, "\(item.name) step \(i)")
                if let periods = step.periods { XCTAssertEqual(events.first?.periodIDs, periods, item.name) }
            }
        }
    }
    func testSharedWarningCases() throws {
        struct Step: Decodable { let remaining: Int; let used: Double?; let second: Int?; let reset: Double?; let threshold: Int?; let age: Double?; let seconds: Double?; let epoch: String?; let restart: Bool?; let confirm: Bool?; let expected: [NotificationCategory] }
        struct Case: Decodable { let name: String; let steps: [Step] }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/notifications/warning-cases.json").standardizedFileURL
        for item in try JSONDecoder().decode([Case].self, from: Data(contentsOf: url)) {
            var e = QuotaWarningEngine()
            for (i, step) in item.steps.enumerated() {
                if step.restart == true { e = QuotaWarningEngine(state: try JSONDecoder().decode(QuotaWarningState.self, from: JSONEncoder().encode(e.state))) }
                if step.confirm == true { e.confirmRecovery(periodIDs: ["primary", "secondary"]) }
                let o = observation(step.remaining, i+1, reset: step.reset ?? 3600, second: step.second, epoch: step.epoch ?? "a", age: step.age ?? 0, time: step.seconds, used: step.used)
                XCTAssertEqual(e.observe(o, threshold: step.threshold ?? 20, now: now.addingTimeInterval(step.seconds ?? Double(i+1)*20)).map(\.category), step.expected, item.name)
            }
        }
    }
    func testCrossingsOncePerCycleAndDirectZeroOnlyExhaustion() {
        var e = QuotaWarningEngine()
        XCTAssertTrue(observe(&e, 21, 1).isEmpty)
        XCTAssertEqual(observe(&e, 20, 2).map(\.category), [.quotaLow])
        XCTAssertTrue(observe(&e, 30, 3).isEmpty)
        XCTAssertTrue(observe(&e, 19, 4).isEmpty)
        XCTAssertEqual(observe(&e, 0, 5).map(\.category), [.quotaExhausted])
        XCTAssertTrue(observe(&e, 0, 6).isEmpty)
        e.confirmRecovery(periodIDs: ["primary"])
        XCTAssertTrue(observe(&e, 100, 7).isEmpty)
        XCTAssertEqual(observe(&e, 0, 8).map(\.category), [.quotaExhausted])
        var direct = QuotaWarningEngine(); _ = observe(&direct, 50, 1)
        XCTAssertEqual(observe(&direct, 0, 2).map(\.category), [.quotaExhausted])
    }
    func testPersistedFlagsAndRestartBaseline() throws {
        var e = QuotaWarningEngine(); _ = observe(&e, 30, 1); _ = observe(&e, 20, 2)
        let state = try JSONDecoder().decode(QuotaWarningState.self, from: JSONEncoder().encode(e.state))
        var restarted = QuotaWarningEngine(state: state)
        XCTAssertTrue(observe(&restarted, 30, 1).isEmpty)
        XCTAssertTrue(observe(&restarted, 10, 2).isEmpty)
    }
    func testFixedResetAnchorAndThresholdChangeOnlyRebaselineWarnings() {
        var e = QuotaWarningEngine(); _ = observe(&e, 30, 1)
        XCTAssertTrue(observe(&e, 25, 2, reset: 3630).isEmpty)
        XCTAssertTrue(observe(&e, 10, 3, reset: 3660).isEmpty)
        XCTAssertTrue(observe(&e, 40, 4, reset: 3660, threshold: 30).isEmpty)
        XCTAssertTrue(observe(&e, 30, 5, reset: 3660, threshold: 30).isEmpty, "Changing threshold cannot rearm a cycle already observed low")
        var fresh = QuotaWarningEngine(); _ = observe(&fresh, 40, 1)
        XCTAssertTrue(observe(&fresh, 40, 2, threshold: 30).isEmpty)
        XCTAssertEqual(observe(&fresh, 30, 3, threshold: 30).map(\.category), [.quotaLow])
    }
    func testUnknownStaleOutOfOrderAndDualWindowMerge() {
        var e = QuotaWarningEngine(); _ = observe(&e, 30, 1, second: 30)
        XCTAssertEqual(observe(&e, 20, 2, second: 20).first?.periodIDs, ["primary", "secondary"])
        XCTAssertTrue(observe(&e, 0, 1, second: 0).isEmpty)
        var fresh = QuotaWarningEngine(); _ = observe(&fresh, 30, 1, second: 30)
        _ = observe(&fresh, 30, 2)
        XCTAssertTrue(observe(&fresh, 30, 3, second: 0).isEmpty, "Missing period is not a cross-line baseline")
        let stale = observation(0, 4, age: 121)
        XCTAssertTrue(fresh.observe(stale, threshold: 20, now: now.addingTimeInterval(80)).isEmpty)
    }
}
