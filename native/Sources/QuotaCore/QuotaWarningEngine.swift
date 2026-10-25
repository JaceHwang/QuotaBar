import Foundation

public struct QuotaWarningPeriodState: Codable, Sendable {
    public var resetAnchor: Date
    public var windowMinutes: Int
    public var lowNotified = false
    public var exhaustionNotified = false
    public var incident = 0
}
public struct QuotaWarningState: Codable, Sendable {
    public var schema = 1
    public var epoch = ""
    public var plan = ""
    public var threshold = 20
    public var periods: [String: QuotaWarningPeriodState] = [:]
    public init() {}
}
public struct QuotaWarningEvent: Sendable {
    public let category: NotificationCategory
    public let periodIDs: [String]
    public let threshold: Int
    public let incidentID: String
}
/// Pure cross-line detector. Fresh availability can rearm depletion without emitting a recovery alert.
public struct QuotaWarningEngine: Sendable {
    public private(set) var state: QuotaWarningState
    private var previous: [String: Double] = [:]
    private var availableSince: [String: Date] = [:]
    private var sequence = -1
    private var receivedAt: Date?
    public init(state: QuotaWarningState = QuotaWarningState()) {
        self.state = state.schema == 1 && state.periods.count <= 2 ? state : QuotaWarningState()
    }
    public mutating func resetBaseline() { previous = [:]; availableSince = [:]; sequence = -1; receivedAt = nil }
    public mutating func confirmRecovery(periodIDs: [String]) {
        for id in periodIDs { state.periods[id]?.exhaustionNotified = false; availableSince[id] = nil }
    }
    public mutating func observe(_ observation: QuotaObservation, threshold: Int, now: Date) -> [QuotaWarningEvent] {
        let o = observation
        guard o.source == .fullRead, now.timeIntervalSince(o.receivedAt) >= -5, now.timeIntervalSince(o.receivedAt) <= 120 else { return [] }
        if state.epoch != o.epoch { state = QuotaWarningState(); state.epoch = o.epoch; resetBaseline() }
        guard o.sequence > sequence, receivedAt.map({ o.receivedAt >= $0 }) ?? true else { return [] }
        sequence = o.sequence; receivedAt = o.receivedAt
        let windows: [(String, QuotaWindowSnapshot?)] = [("primary", o.quota.primary), ("secondary", o.quota.secondary)]
        guard let plan = o.quota.planType?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty,
              windows.compactMap(\.1).allSatisfy({ $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && ($0.windowDurationMins ?? 0) > 0 && $0.resetsAt.timeIntervalSince1970.isFinite }) else {
            previous = [:]; availableSince = [:]; return []
        }
        if state.plan != plan { state.periods = [:]; previous = [:]; availableSince = [:]; state.plan = plan }
        let threshold = (1...99).contains(threshold) ? threshold : 20
        if state.threshold != threshold {
            state.threshold = threshold; previous = [:]
        }
        var groups: [NotificationCategory: [String]] = [:]
        var identities: [NotificationCategory: [String]] = [:]
        for (id, window) in windows {
            guard let window else { previous[id] = nil; availableSince[id] = nil; continue }
            let remaining = 100 - window.usedPercent
            let minutes = window.windowDurationMins!
            var period = state.periods[id] ?? QuotaWarningPeriodState(resetAnchor: window.resetsAt, windowMinutes: minutes)
            let drift = window.resetsAt.timeIntervalSince(period.resetAnchor)
            if period.windowMinutes != minutes || drift >= 60 || drift < 0 {
                // Backwards metadata is unknown. Establish one baseline at the new fixed anchor.
                period = QuotaWarningPeriodState(resetAnchor: window.resetsAt, windowMinutes: minutes)
                previous[id] = nil; availableSince[id] = nil
            }
            if period.exhaustionNotified && remaining >= 1 {
                if let since = availableSince[id] {
                    let elapsed = o.receivedAt.timeIntervalSince(since)
                    if elapsed > 120 { availableSince[id] = o.receivedAt }
                    else if elapsed >= 15 { period.exhaustionNotified = false; availableSince[id] = nil }
                } else { availableSince[id] = o.receivedAt }
            } else { availableSince[id] = nil }
            let old = previous[id]
            var category: NotificationCategory?
            if let old {
                if old > 0 && remaining <= 0 && !period.exhaustionNotified {
                    category = .quotaExhausted; period.exhaustionNotified = true; period.incident += 1
                } else if old > Double(threshold) && remaining > 0 && remaining <= Double(threshold) && !period.lowNotified {
                    category = .quotaLow; period.lowNotified = true
                }
            } else {
                // Restart/first sample never creates a historical cross-line event.
                period.lowNotified = period.lowNotified || remaining <= Double(threshold)
                period.exhaustionNotified = period.exhaustionNotified || remaining <= 0
            }
            state.periods[id] = period; previous[id] = remaining
            if let category {
                groups[category, default: []].append(id)
                identities[category, default: []].append("\(id):\(period.resetAnchor.timeIntervalSince1970):\(period.incident)")
            }
        }
        return groups.keys.sorted { $0.priority < $1.priority }.map { category in
            QuotaWarningEvent(category: category, periodIDs: groups[category]!, threshold: threshold,
                              incidentID: "\(state.epoch):\(category.rawValue):\(threshold):" + identities[category]!.joined(separator: "|"))
        }
    }
}
