import Foundation

public enum NotificationDeliveryMode: String, Codable, Sendable, CaseIterable { case bubble, system, both, off
    public var usesBubble: Bool { self == .bubble || self == .both }
    public var usesSystem: Bool { self == .system || self == .both }
}
public struct NotificationPresentationPreferences: Codable, Equatable, Sendable {
    public var schema = 1
    public var mode: NotificationDeliveryMode
    public var pausedUntil: Date?
    public init(mode: NotificationDeliveryMode = .bubble, pausedUntil: Date? = nil) { self.mode = mode; self.pausedUntil = pausedUntil }
    private enum CodingKeys: String, CodingKey { case schema, mode, pausedUntil }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(NotificationDeliveryMode.self, forKey: .mode)) ?? .bubble
        pausedUntil = try? c.decode(Date.self, forKey: .pausedUntil)
        if (try? c.decode(Int.self, forKey: .schema)) ?? 1 != 1 { mode = .bubble; pausedUntil = nil }
    }
    public func paused(now: Date) -> Bool { pausedUntil.map { $0 > now } ?? false }
}
public struct NotificationUnreadItem: Sendable {
    public let message: ExperienceNotification
    public var stale: Bool
    public init(message: ExperienceNotification, stale: Bool) { self.message = message; self.stale = stale }
}
/// Pure presentation state. All clocks and actual delivery live in native adapters.
public struct NotificationPresentationState: Sendable {
    private struct Entry: Sendable { let message: ExperienceNotification; var deferred: Bool; var presented = false; var read = false }
    private var entries: [Entry] = []
    public private(set) var activeID: String?
    private var quotaBaseline: QuotaObservation?
    private var stopped = false
    public init() {}
    public mutating func enqueue(_ m: ExperienceNotification, canPresent: Bool, now: Date) {
        guard !stopped, !entries.contains(where: { $0.message.id == m.id }) else { return }
        prune(now)
        entries.append(Entry(message: m, deferred: !canPresent))
        if entries.count > 32 {
            let worst = entries.filter { $0.message.id != activeID }.map { $0.message.kind.rawValue }.max()
            if let i = entries.firstIndex(where: { $0.message.id != activeID && $0.message.kind.rawValue == worst }) { entries.remove(at: i) }
        }
    }
    public mutating func next(canPresent: Bool, now: Date) -> ExperienceNotification? {
        prune(now)
        guard !stopped, canPresent, activeID == nil else { return nil }
        let candidates = entries.indices.filter { !entries[$0].deferred && !entries[$0].presented && !entries[$0].read && entries[$0].message.valid(now: now) }
        guard let i = candidates.min(by: { entries[$0].message.kind.rawValue < entries[$1].message.kind.rawValue }) else { return nil }
        activeID = entries[i].message.id
        return entries[i].message
    }
    public mutating func shown(id: String, now: Date) {
        guard activeID == id, let i = entries.firstIndex(where: { $0.message.id == id }) else { return }
        entries[i].presented = true
    }
    public mutating func dismiss(id: String, read: Bool) {
        if let i = entries.firstIndex(where: { $0.message.id == id }) { entries[i].read = read || entries[i].read; entries[i].deferred = true }
        if activeID == id { activeID = nil }
    }
    // All bubble kinds are held until a fresh full read proves a quota change.
    public mutating func setInteracting(_ value: Bool, now: Date) {}
    @discardableResult public mutating func tick(now: Date) -> Bool { prune(now); return false }
    @discardableResult public mutating func observeQuota(_ observation: QuotaObservation, now: Date) -> Bool {
        guard !stopped, observation.source == .fullRead,
              now.timeIntervalSince(observation.receivedAt) >= -5,
              now.timeIntervalSince(observation.receivedAt) <= 120,
              observation.quota.primary.usedPercent.isFinite,
              observation.quota.primary.usedPercent >= 0, observation.quota.primary.usedPercent <= 100,
              observation.quota.secondary.map({ $0.usedPercent.isFinite && $0.usedPercent >= 0 && $0.usedPercent <= 100 }) ?? true else { return false }
        let previous = quotaBaseline
        if let previous, previous.epoch == observation.epoch {
            guard observation.sequence > previous.sequence, observation.receivedAt >= previous.receivedAt else { return false }
        }
        let changed = previous.map { old in
            old.epoch == observation.epoch &&
            (old.quota.primary.usedPercent != observation.quota.primary.usedPercent ||
             (old.quota.secondary != nil && observation.quota.secondary != nil && old.quota.secondary?.usedPercent != observation.quota.secondary?.usedPercent))
        } ?? false
        // Missing optional periods are unknown, not zero. Preserve only their comparison baseline.
        var quota = observation.quota
        if quota.secondary == nil, let previous, previous.epoch == observation.epoch {
            quota = AllowanceSnapshot(usedPercent: quota.primary.usedPercent, remainingPercent: quota.primary.remainingPercent, resetsAt: quota.primary.resetsAt, receivedAt: quota.receivedAt, windowDurationMins: quota.primary.windowDurationMins, planType: quota.planType, secondary: previous.quota.secondary)
        }
        quotaBaseline = QuotaObservation(epoch: observation.epoch, sequence: observation.sequence, receivedAt: observation.receivedAt, quota: quota, source: .fullRead)
        guard changed, let id = activeID else { return false }
        dismiss(id: id, read: false); return true
    }
    public mutating func suspend() { if let id = activeID { dismiss(id: id, read: false) } }
    public mutating func forget(id: String) { if activeID == id { suspend() }; entries.removeAll { $0.message.id == id } }
    public mutating func cancel(epoch: String) {
        if entries.contains(where: { $0.message.id == activeID && $0.message.epoch == epoch }) { suspend() }
        entries.removeAll { $0.message.epoch == epoch }
    }
    public mutating func unread(now: Date) -> [NotificationUnreadItem] {
        prune(now)
        return entries.filter { !$0.read }.reversed().map { NotificationUnreadItem(message: $0.message, stale: !$0.message.valid(now: now)) }
    }
    public mutating func stop() { suspend(); entries = []; stopped = true }
    private mutating func prune(_ now: Date) {
        entries.removeAll { $0.message.id != activeID && now.timeIntervalSince($0.message.createdAt) > 86400 }
    }
}
