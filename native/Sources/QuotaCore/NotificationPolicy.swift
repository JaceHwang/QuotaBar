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
    public var lowRemainingThresholds: [Int]?
    public var bankExpiryHours: [Int]?
    public var bankThresholdChannels: [Int: Set<NotificationChannel>]?
    public static func normalize(_ values: [Int], range: ClosedRange<Int>) -> [Int] { Array(Set(values.filter { range.contains($0) }).sorted(by: >).prefix(32)) }
    public var configuredLowThresholds: [Int] { Self.normalize(lowRemainingThresholds ?? [lowRemainingThreshold], range: 1...99) }
    public var configuredBankHours: [Int] { Self.normalize(bankExpiryHours ?? [72,24], range: 1...8760) }
    public func bankChannels(for hours: Int) -> Set<NotificationChannel> {
        if let bankThresholdChannels { return bankThresholdChannels[hours] ?? [] }
        return rules[hours == 24 ? .bankExpiring24h : .bankExpiring72h] ?? []
    }
    public var commonBankChannels: Set<NotificationChannel> {
        let sets = configuredBankHours.isEmpty ? [rules[.bankExpiring72h] ?? [], rules[.bankExpiring24h] ?? []] : configuredBankHours.map { bankChannels(for: $0) }
        return sets.reduce(Set(NotificationChannel.allCases)) { $0.intersection($1) }
    }
    public func bankChannelSelected(_ channel: NotificationChannel) -> Bool? {
        let sets = configuredBankHours.isEmpty ? [rules[.bankExpiring72h] ?? [], rules[.bankExpiring24h] ?? []] : configuredBankHours.map { bankChannels(for: $0) }
        let selected = sets.filter { $0.contains(channel) }.count
        return selected == 0 ? false : selected == sets.count ? true : nil
    }
    public mutating func setLowThresholds(_ values: [Int]) {
        lowRemainingThresholds = Self.normalize(values, range: 1...99)
        if let first = lowRemainingThresholds?.first { lowRemainingThreshold = first }
    }
    public mutating func setBankHours(_ values: [Int], retainingChannelsFrom aliases: [Int:Int] = [:]) {
        let hours = Self.normalize(values, range: 1...8760), inherited = commonBankChannels
        let existing = Set(configuredBankHours)
        let mapping = Dictionary(uniqueKeysWithValues: hours.map { hour in
            (hour, aliases[hour].map { bankChannels(for: $0) } ?? (existing.contains(hour) ? bankChannels(for: hour) : inherited))
        })
        if hours.isEmpty {
            rules[.bankExpiring72h] = inherited
            rules[.bankExpiring24h] = inherited
        }
        bankExpiryHours = hours; bankThresholdChannels = mapping
    }
    public mutating func setBankChannel(_ channel: NotificationChannel, enabled: Bool) {
        var mapping = Dictionary(uniqueKeysWithValues: configuredBankHours.map { ($0, bankChannels(for: $0)) })
        for hour in configuredBankHours { if enabled { mapping[hour, default: []].insert(channel) } else { mapping[hour]?.remove(channel) } }
        bankThresholdChannels = mapping
        for category in [NotificationCategory.bankExpiring72h, .bankExpiring24h] {
            if enabled { rules[category, default: []].insert(channel) } else { rules[category]?.remove(channel) }
        }
    }
    public mutating func selectColumn(_ channel: NotificationChannel) {
        for category in NotificationCategory.allCases { rules[category, default: []].insert(channel) }
        setBankChannel(channel, enabled: true)
    }
    public mutating func toggleColumn(_ channel: NotificationChannel) {
        let ordinary = NotificationCategory.allCases.filter { $0 != .bankExpiring72h && $0 != .bankExpiring24h }
        let enabled = !(ordinary.allSatisfy { rules[$0]?.contains(channel) == true } && bankChannelSelected(channel) == true)
        for category in NotificationCategory.allCases {
            if enabled { rules[category, default: []].insert(channel) } else { rules[category]?.remove(channel) }
        }
        setBankChannel(channel, enabled: enabled)
    }
    public var bubblePausedUntil: Date?
    public init() {
        rules = Dictionary(uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, [.quotaRecovered, .bankExpiring72h, .bankExpiring24h].contains($0) ? [.bubble] : []) })
    }
    public static func allSelected() -> NotificationPolicyPreferences {
        var p = NotificationPolicyPreferences()
        p.rules = Dictionary(uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, Set(NotificationChannel.allCases)) })
        return p
    }
    private enum CodingKeys: String, CodingKey { case schema, enabledChannels, rules, lowRemainingThreshold, bubblePausedUntil, lowRemainingThresholds, bankExpiryHours, bankThresholdChannels }
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
        lowRemainingThreshold = (1...99).contains(threshold) ? threshold : 20
        lowRemainingThresholds = c.contains(.lowRemainingThresholds) ? Self.normalize((try? c.decode([Int].self, forKey: .lowRemainingThresholds)) ?? [], range: 1...99) : nil
        bankExpiryHours = c.contains(.bankExpiryHours) ? Self.normalize((try? c.decode([Int].self, forKey: .bankExpiryHours)) ?? [], range: 1...8760) : nil
        bankThresholdChannels = c.contains(.bankThresholdChannels) ? (try? c.decode([Int: Set<NotificationChannel>].self, forKey: .bankThresholdChannels)) ?? [:] : nil
        bubblePausedUntil = try? c.decode(Date.self, forKey: .bubblePausedUntil)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema); try c.encode(enabledChannels, forKey: .enabledChannels)
        try c.encode(Dictionary(uniqueKeysWithValues: rules.map { ($0.key.rawValue, $0.value) }), forKey: .rules)
        try c.encode(lowRemainingThreshold, forKey: .lowRemainingThreshold)
        try c.encodeIfPresent(bubblePausedUntil, forKey: .bubblePausedUntil)
        try c.encodeIfPresent(lowRemainingThresholds, forKey: .lowRemainingThresholds)
        try c.encodeIfPresent(bankExpiryHours, forKey: .bankExpiryHours)
        try c.encodeIfPresent(bankThresholdChannels, forKey: .bankThresholdChannels)
    }
}
public enum NotificationPolicy {
    public static func decision(category: NotificationCategory, channel: NotificationChannel, preferences: NotificationPolicyPreferences, now: Date, threshold: Int? = nil) -> NotificationDecision {
        var selected = preferences.rules[category] ?? []
        if let threshold {
            if category == .quotaLow && !preferences.configuredLowThresholds.contains(threshold) { return .ruleOff }
            if category == .bankExpiring72h || category == .bankExpiring24h {
                guard preferences.configuredBankHours.contains(threshold) else { return .ruleOff }
                selected = preferences.bankChannels(for: threshold)
            }
        }
        guard selected.contains(channel) else { return .ruleOff }
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
