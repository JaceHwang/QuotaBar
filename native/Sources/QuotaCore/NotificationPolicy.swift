import Foundation

public enum NotificationCategory: String, Codable, CaseIterable, Sendable {
    case quotaRecovered, bankExpiring72h, bankExpiring24h, updateAvailable, quotaLow, quotaExhausted
    public var priority: Int {
        switch self { case .quotaExhausted: 0; case .quotaLow: 1; case .quotaRecovered: 2; case .bankExpiring72h, .bankExpiring24h: 3; case .updateAvailable: 4 }
    }
}
public enum NotificationChannel: String, Codable, CaseIterable, Sendable { case bubble, system, mobile }
public enum NotificationDecision: String, Sendable { case allowed, ruleOff, channelOff, paused }
public struct NotificationPolicyPreferences: Codable, Equatable, Sendable {
    public private(set) var recoveredInvalidData = false
    public var schema = 1
    public var enabledChannels: Set<NotificationChannel> = [.bubble]
    public var rules: [NotificationCategory: Set<NotificationChannel>]
    public var lowRemainingThreshold = 20
    public var bubblePausedUntil: Date?
    public init() {
        rules = Dictionary(uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, [.quotaRecovered, .bankExpiring72h, .bankExpiring24h].contains($0) ? [.bubble] : []) })
    }
    private enum CodingKeys: String, CodingKey { case schema, enabledChannels, rules, lowRemainingThreshold, bubblePausedUntil }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A malformed policy cannot silently enable a remote channel.
        guard (try? c.decode(Int.self, forKey: .schema)) == 1,
              let channels = try? c.decode(Set<NotificationChannel>.self, forKey: .enabledChannels),
              let raw = try? c.decode([String: Set<NotificationChannel>].self, forKey: .rules) else {
            enabledChannels = []; rules = [:]; recoveredInvalidData = true; return
        }
        enabledChannels = channels
        rules = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in NotificationCategory(rawValue: key).map { ($0, value) } })
        let threshold = (try? c.decode(Int.self, forKey: .lowRemainingThreshold)) ?? 20
        lowRemainingThreshold = [10, 20, 30].contains(threshold) ? threshold : 20
        bubblePausedUntil = try? c.decode(Date.self, forKey: .bubblePausedUntil)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema); try c.encode(enabledChannels, forKey: .enabledChannels)
        try c.encode(Dictionary(uniqueKeysWithValues: rules.map { ($0.key.rawValue, $0.value) }), forKey: .rules)
        try c.encode(lowRemainingThreshold, forKey: .lowRemainingThreshold)
        try c.encodeIfPresent(bubblePausedUntil, forKey: .bubblePausedUntil)
    }
}
public enum NotificationPolicy {
    public static func decision(category: NotificationCategory, channel: NotificationChannel, preferences: NotificationPolicyPreferences, now: Date) -> NotificationDecision {
        guard preferences.rules[category]?.contains(channel) == true else { return .ruleOff }
        guard preferences.enabledChannels.contains(channel) else { return .channelOff }
        if channel == .bubble, let until = preferences.bubblePausedUntil, now < until { return .paused }
        return .allowed
    }
}

public struct LegacyNotificationPreferences: Sendable {
    public let mode: NotificationDeliveryMode
    public let recovery: Bool
    public let celebration: Bool
    public let bank: Bool
    public let updatesReminders: Bool
    public let barkEnabled: Bool
    public let pausedUntil: Date?
    public init(mode: NotificationDeliveryMode, recovery: Bool, celebration: Bool, bank: Bool, updatesReminders: Bool, barkEnabled: Bool, pausedUntil: Date? = nil) {
        self.mode = mode; self.recovery = recovery; self.celebration = celebration; self.bank = bank
        self.updatesReminders = updatesReminders; self.barkEnabled = barkEnabled; self.pausedUntil = pausedUntil
    }
}
public enum NotificationPolicyMigration {
    public static func migrate(legacy: LegacyNotificationPreferences) -> NotificationPolicyPreferences {
        var channels: Set<NotificationChannel> = []
        if legacy.mode.usesBubble { channels.insert(.bubble) }
        if legacy.mode.usesSystem { channels.insert(.system) }
        if legacy.barkEnabled { channels.insert(.mobile) }
        var p = NotificationPolicyPreferences()
        p.enabledChannels = channels; p.bubblePausedUntil = legacy.pausedUntil
        for category in NotificationCategory.allCases {
            let enabled: Bool
            switch category {
            case .quotaRecovered: enabled = legacy.recovery || legacy.celebration
            case .bankExpiring72h, .bankExpiring24h: enabled = legacy.bank
            case .updateAvailable: enabled = legacy.updatesReminders
            case .quotaLow, .quotaExhausted: enabled = false
            }
            p.rules[category] = enabled ? channels : []
        }
        return p
    }
}
