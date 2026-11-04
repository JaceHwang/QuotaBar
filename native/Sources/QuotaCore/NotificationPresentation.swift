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
    private var stopped = false
    public init() {}
    public mutating func enqueue(_ m: ExperienceNotification, canPresent: Bool, now: Date) {
        guard !stopped, !entries.contains(where: { $0.message.id == m.id }) else { return }
        prune(now)
        entries.append(Entry(message: m, deferred: !canPresent))
        if entries.count > 32 {
            let worst = entries.filter { $0.message.id != activeID }.map { $0.message.priority }.max()
            if let i = entries.firstIndex(where: { $0.message.id != activeID && $0.message.priority == worst }) { entries.remove(at: i) }
        }
    }
    public mutating func next(canPresent: Bool, now: Date) -> ExperienceNotification? {
        prune(now)
        guard !stopped, canPresent, activeID == nil else { return nil }
        let candidates = entries.indices.filter { !entries[$0].deferred && !entries[$0].presented && !entries[$0].read && entries[$0].message.valid(now: now) }
        guard let i = candidates.min(by: { entries[$0].message.priority < entries[$1].message.priority }) else { return nil }
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
    // Presentation ends only through explicit dismissal or lifecycle cancellation.
    public mutating func setInteracting(_ value: Bool, now: Date) {}
    @discardableResult public mutating func tick(now: Date) -> Bool { prune(now); return false }
    @discardableResult public mutating func observeQuota(_ observation: QuotaObservation, now: Date) -> Bool { false }
    public mutating func suspend() { if let id = activeID { dismiss(id: id, read: false) } }
    public mutating func forget(id: String) { if activeID == id { suspend() }; entries.removeAll { $0.message.id == id } }
    public mutating func cancel(epoch: String, preserving id: String? = nil) {
        if entries.contains(where: { $0.message.id == activeID && $0.message.epoch == epoch && $0.message.id != id }) { suspend() }
        entries.removeAll { $0.message.epoch == epoch && $0.message.id != id }
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
