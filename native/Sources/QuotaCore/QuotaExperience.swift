import Foundation
import CryptoKit

public struct QuotaExperiencePreferences: Codable, Equatable, Sendable {
    public var moods: Bool
    public var recovery: Bool
    public var celebration: Bool
    public var recoveryNotificationEnabled: Bool { recovery || celebration }
    public var bank: Bool
    public init(moods: Bool = true, recovery: Bool = true, celebration: Bool = true, bank: Bool = true) {
        self.moods = moods; self.recovery = recovery; self.celebration = celebration; self.bank = bank
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        moods = try values.decodeIfPresent(Bool.self, forKey: .moods) ?? true
        recovery = try values.decodeIfPresent(Bool.self, forKey: .recovery) ?? true
        celebration = try values.decodeIfPresent(Bool.self, forKey: .celebration) ?? true
        bank = try values.decodeIfPresent(Bool.self, forKey: .bank) ?? true
    }
}
public enum QuotaMood: String, Sendable {
    case good, low, exhausted, unavailable, recovered
    public static func resolve(_ quota: AllowanceSnapshot?, ready: Bool, now: Date) -> QuotaMood {
        guard ready, let quota, now.timeIntervalSince(quota.receivedAt) <= 120,
              now.timeIntervalSince(quota.receivedAt) >= -5 else { return .unavailable }
        let windows = [quota.primary, quota.secondary].compactMap { $0 }
        guard windows.allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 && $0.usedPercent <= 100 }) else { return .unavailable }
        if windows.contains(where: { $0.usedPercent >= 100 }) { return .exhausted }
        return windows.contains(where: { $0.usedPercent >= 80 }) ? .low : .good
    }
}
public enum BankFieldState: String, Sendable { case omitted, null, value }
public enum ObservationSource: String, Sendable { case fullRead, notification }
public struct QuotaObservation: Equatable, Sendable {
    public let epoch: String
    public let sequence: Int
    public let receivedAt: Date
    public let quota: AllowanceSnapshot
    public let bankFieldState: BankFieldState
    public let source: ObservationSource
    public init(epoch: String, sequence: Int, receivedAt: Date, quota: AllowanceSnapshot, bankFieldState: BankFieldState = .omitted, source: ObservationSource = .fullRead) {
        self.epoch = epoch; self.sequence = sequence; self.receivedAt = receivedAt; self.quota = quota
        self.bankFieldState = bankFieldState; self.source = source
    }
    public static func decode(_ data: Data, epoch: String, sequence: Int, receivedAt: Date = Date()) throws -> QuotaObservation {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = root["result"] as? [String: Any] ?? root
        let field: BankFieldState = result["rateLimitResetCredits"] == nil ? .omitted : (result["rateLimitResetCredits"] is NSNull ? .null : .value)
        return QuotaObservation(epoch: epoch, sequence: sequence, receivedAt: receivedAt, quota: try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt), bankFieldState: field)
    }
}
public struct BankReceipt: Codable, Sendable {
    public var stage: Int
    public var expiresAt: Date
}
public struct ExperienceState: Codable, Sendable {
    public var schema = 1
    public var epoch: String
    public var receipts: [String: BankReceipt] = [:]
    public var pendingBankBaselines: Set<Int>? = nil
    public init(epoch: String = UUID().uuidString) { self.epoch = epoch }
}
public struct BankExpiryEvent: Equatable, Sendable {
    public let key: String
    public let stage: Int
    public let count: Int
    public let expiresAt: Date
}
public struct ExperienceUpdate: Sendable {
    public var recoveries: [String] = []
    public var bank: [BankExpiryEvent] = []
}
/// Serial, platform-independent event detection. Display merging is deliberately outside this type.
public struct QuotaExperienceEngine: Sendable {
    public private(set) var state: ExperienceState
    public private(set) var preferences = QuotaExperiencePreferences()
    private var baseline: AllowanceSnapshot?
    private var sequence = -1
    private struct Candidate: Sendable { let old: QuotaWindowSnapshot; let at: Date }
    private var candidates: [String: Candidate] = [:]
    private var suppressFirstBank: Bool
    public init(state: ExperienceState, suppressFirstBank: Bool = false) { self.state = state; self.suppressFirstBank = suppressFirstBank }
    public mutating func configure(_ value: QuotaExperiencePreferences) {
        if preferences.recovery != value.recovery || preferences.celebration != value.celebration { resetBaseline() }
        preferences = value
    }
    public mutating func suppressBankStages(_ stages: Set<Int>) {
        state.pendingBankBaselines = (state.pendingBankBaselines ?? []).union(stages.filter { (1...8760).contains($0) })
    }
    public mutating func resetBaseline() { baseline = nil; candidates = [:]; sequence = -1 }
    public mutating func rotateEpoch() { state = ExperienceState(); resetBaseline(); suppressFirstBank = false }
    public mutating func observe(_ o: QuotaObservation, now: Date, bankThresholds: [Int] = [72, 24]) -> ExperienceUpdate {
        let thresholds = Self.normalizeBankThresholds(bankThresholds)
        var output = ExperienceUpdate()
        guard o.epoch == state.epoch, o.source == .fullRead, o.sequence > sequence,
              now.timeIntervalSince(o.receivedAt) >= -5, now.timeIntervalSince(o.receivedAt) <= 120 else { return output }
        sequence = o.sequence
        let q = o.quota
        let valid = [q.primary, q.secondary].compactMap { $0 }.allSatisfy { $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }
        guard valid else { resetBaseline(); return output }
        if preferences.recovery || preferences.celebration {
            let metadataKnown = q.planType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && (q.primary.windowDurationMins ?? 0) > 0 && (q.secondary == nil || (q.secondary?.windowDurationMins ?? 0) > 0)
            let compatible = metadataKnown && (baseline.map { $0.planType == q.planType && $0.primary.windowDurationMins == q.primary.windowDurationMins && $0.secondary?.windowDurationMins == q.secondary?.windowDurationMins && ($0.secondary != nil) == (q.secondary != nil) } ?? false)
            if compatible, let previous = baseline {
                for (name, old, current) in [("primary", previous.primary, q.primary), ("secondary", previous.secondary, q.secondary)] {
                    guard let old, let current else { continue }
                    if let pending = candidates[name] {
                        let elapsed = o.receivedAt.timeIntervalSince(pending.at)
                        if elapsed > 120 || !Self.restored(pending.old, current) { candidates[name] = nil }
                        else if elapsed >= 15 { output.recoveries.append(name); candidates[name] = nil }
                    } else if Self.restored(old, current) { candidates[name] = Candidate(old: old, at: o.receivedAt) }
                }
            } else { candidates = [:] }
            baseline = q
        }
        if preferences.bank, o.bankFieldState == .value, let bank = q.bank {
            output.bank = bankEvents(bank, now: now, thresholds: thresholds)
            if let pending = state.pendingBankBaselines { output.bank.removeAll { pending.contains($0.stage) }; if bankInventoryIsComplete(bank) { state.pendingBankBaselines = nil } }
            if suppressFirstBank {
                output.bank = []
                if bankInventoryIsComplete(bank) { suppressFirstBank = false }
            }
        }
        state.receipts = state.receipts.filter { $0.value.expiresAt > now.addingTimeInterval(-86400) && $0.value.expiresAt < now.addingTimeInterval(8760*3600 + 1) }
        if state.receipts.count > 2048 {
            state.receipts = Dictionary(uniqueKeysWithValues: state.receipts.sorted { $0.key < $1.key }.prefix(2048).map { ($0.key, $0.value) })
            output.bank = [] // fail closed if inventory exceeds bounded receipt capacity
        }
        return output
    }
    private static func normalizeBankThresholds(_ values: [Int]) -> [Int] {
        Array(Set(values.filter { (1...8760).contains($0) }).sorted(by: >).prefix(32))
    }
    private static func bankStage(remaining: TimeInterval, thresholds: [Int]) -> Int? {
        thresholds.last { remaining <= Double($0)*3600 }
    }
    private static func restored(_ old: QuotaWindowSnapshot, _ new: QuotaWindowSnapshot) -> Bool {
        let delta = new.resetsAt.timeIntervalSince(old.resetsAt)
        return (old.usedPercent >= 100 && new.usedPercent <= 99)
            || (delta >= 60 && old.usedPercent - new.usedPercent >= 10)
            || (abs(delta) < 60 && old.usedPercent >= 10 && new.usedPercent <= 1)
    }
    private func bankKey(_ c: BankResetCredit) -> String {
        let identity = c.id.map { "id:\($0)" } ?? "fallback:\(c.grantedAt?.timeIntervalSince1970 ?? 0):\(c.resetType ?? "")"
        return SHA256.hash(data: Data("\(state.epoch)|\(identity)|\(c.expiresAt?.timeIntervalSince1970 ?? 0)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func bankEventsAreCurrent(_ events: [BankExpiryEvent], observation: QuotaObservation, now: Date, bankThresholds: [Int] = [72, 24]) -> Bool {
        let thresholds = Self.normalizeBankThresholds(bankThresholds)
        guard !thresholds.isEmpty, !events.isEmpty, observation.epoch == state.epoch, observation.source == .fullRead, observation.bankFieldState == .value,
              now.timeIntervalSince(observation.receivedAt) >= -5, now.timeIntervalSince(observation.receivedAt) <= 120,
              let bank = observation.quota.bank, bank.availableCount > 0, let credits = bank.credits else { return false }
        var inventory: [String: Int] = [:]
        for credit in credits where credit.status == "available" {
            guard let expires = credit.expiresAt, expires > now, expires <= now.addingTimeInterval(Double(thresholds.first ?? 0)*3600) else { continue }
            let key = bankKey(credit)
            inventory[key] = credit.id == nil ? (inventory[key] ?? 0)+1 : 1
        }
        guard inventory.values.reduce(0, +) <= bank.availableCount, events.reduce(0, { $0+$1.count }) <= bank.availableCount else { return false }
        return events.allSatisfy { event in
            let matched = credits.filter { $0.status == "available" && bankKey($0) == event.key }
            let count = matched.first?.id == nil ? matched.count : min(1, matched.count)
            let remaining = event.expiresAt.timeIntervalSince(now)
            return event.count > 0 && count >= event.count && remaining > 0 && Self.bankStage(remaining: remaining, thresholds: thresholds) == event.stage
        }
    }
    private func bankInventoryIsComplete(_ bank: BankResetSummary) -> Bool {
        guard bank.availableCount >= 0 else { return false }
        let available = bank.credits?.filter { $0.status == "available" } ?? []
        if bank.availableCount == 0 { return available.isEmpty }
        guard bank.credits != nil, available.allSatisfy({ $0.expiresAt != nil }) else { return false }
        let groups = Dictionary(grouping: available, by: bankKey)
        return groups.values.reduce(0) { $0 + ($1.first?.id == nil ? $1.count : 1) } == bank.availableCount
    }
    private mutating func bankEvents(_ bank: BankResetSummary, now: Date, thresholds: [Int]) -> [BankExpiryEvent] {
        guard !thresholds.isEmpty, bank.availableCount > 0, let credits = bank.credits else { return [] }
        var groups: [String: (count: Int, expires: Date)] = [:]
        for c in credits where c.status == "available" {
            guard let expires = c.expiresAt, expires > now, expires <= now.addingTimeInterval(Double(thresholds.first ?? 0)*3600) else { continue }
            let key = bankKey(c)
            let previous = groups[key]
            groups[key] = (c.id == nil ? (previous?.count ?? 0)+1 : 1, expires)
        }
        guard groups.values.reduce(0, { $0+$1.count }) <= bank.availableCount else { return [] }
        return groups.sorted { $0.key < $1.key }.compactMap { key, group in
            guard let stage = Self.bankStage(remaining: group.expires.timeIntervalSince(now), thresholds: thresholds) else { return nil }
            if (suppressFirstBank || state.pendingBankBaselines?.contains(stage) == true) && !bankInventoryIsComplete(bank) { return nil }
            if let receipt = state.receipts[key], receipt.stage <= stage { return nil }
            state.receipts[key] = BankReceipt(stage: stage, expiresAt: group.expires)
            return BankExpiryEvent(key: key, stage: stage, count: group.count, expiresAt: group.expires)
        }
    }
}
