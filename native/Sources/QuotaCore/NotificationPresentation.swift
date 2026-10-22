import Foundation

public enum NotificationDeliveryMode: String, Codable, Sendable, CaseIterable { case bubble, system, both, off
    public var usesBubble: Bool { self == .bubble || self == .both }
    public var usesSystem: Bool { self == .system || self == .both }
}
public struct NotificationPresentationPreferences: Codable, Equatable, Sendable {
    public var mode: NotificationDeliveryMode
    public var pausedUntil: Date?
    public init(mode: NotificationDeliveryMode = .bubble, pausedUntil: Date? = nil) { self.mode = mode; self.pausedUntil = pausedUntil }
    private enum CodingKeys: String, CodingKey { case mode, pausedUntil }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(NotificationDeliveryMode.self, forKey: .mode)) ?? .bubble
        pausedUntil = try? c.decode(Date.self, forKey: .pausedUntil)
    }
    public func paused(now: Date) -> Bool { pausedUntil.map { $0 > now } ?? false }
}
public struct NotificationUnreadItem: Sendable {
    public let message: ExperienceNotification
    public var stale: Bool
}
/// Pure presentation state. All clocks and actual delivery live in native adapters.
public struct NotificationPresentationState: Sendable {
    private struct Entry: Sendable { let message: ExperienceNotification; var deferred: Bool; var presented = false; var read = false }
    private var entries: [Entry] = []
    public private(set) var activeID: String?
    private var deadline: Date?
    private var remaining: TimeInterval = 0
    private var interacting = false
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
        activeID = entries[i].message.id; remaining = [.bank, .update].contains(entries[i].message.kind) ? 10 : 6
        deadline = nil; interacting = false
        return entries[i].message
    }
    public mutating func shown(id: String, now: Date) {
        guard activeID == id, let i = entries.firstIndex(where: { $0.message.id == id }) else { return }
        entries[i].presented = true; deadline = now.addingTimeInterval(remaining)
    }
    public mutating func dismiss(id: String, read: Bool) {
        if let i = entries.firstIndex(where: { $0.message.id == id }) { entries[i].read = read || entries[i].read; entries[i].deferred = true }
        if activeID == id { activeID = nil; deadline = nil; interacting = false }
    }
    public mutating func setInteracting(_ value: Bool, now: Date) {
        guard activeID != nil, value != interacting else { return }
        if value { if let deadline { remaining = max(0, deadline.timeIntervalSince(now)) }; deadline = nil }
        else { deadline = now.addingTimeInterval(remaining) }
        interacting = value
    }
    @discardableResult public mutating func tick(now: Date) -> Bool {
        prune(now)
        guard let id = activeID, let deadline, now >= deadline else { return false }
        dismiss(id: id, read: false); return true
    }
    public mutating func suspend() { if let id = activeID { dismiss(id: id, read: false) } }
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
        if let id = activeID, entries.contains(where: { $0.message.id == id && now.timeIntervalSince($0.message.createdAt) > 86400 }) { suspend() }
        entries.removeAll { now.timeIntervalSince($0.message.createdAt) > 86400 }
    }
}
