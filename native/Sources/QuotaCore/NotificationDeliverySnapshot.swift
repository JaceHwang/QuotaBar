import Foundation

/// Original eligibility never expands when the user enables a channel later.
public struct NotificationDeliverySnapshot: Sendable {
    public let category: NotificationCategory
    public private(set) var eligible: Set<NotificationChannel>
    public private(set) var accepted: Set<NotificationChannel> = []
    public init(category: NotificationCategory, preferences: NotificationPolicyPreferences, now: Date) {
        self.category = category
        eligible = Set(NotificationChannel.allCases.filter { NotificationPolicy.decision(category: category, channel: $0, preferences: preferences, now: now) == .allowed })
    }
    public mutating func restrict(to preferences: NotificationPolicyPreferences, now: Date) {
        eligible = eligible.filter { NotificationPolicy.decision(category: category, channel: $0, preferences: preferences, now: now) == .allowed }
    }
    public func allows(_ channel: NotificationChannel, preferences: NotificationPolicyPreferences, now: Date) -> Bool {
        eligible.contains(channel) && !accepted.contains(channel) && NotificationPolicy.decision(category: category, channel: channel, preferences: preferences, now: now) == .allowed
    }
    public mutating func recordAccepted(_ channel: NotificationChannel) { accepted.insert(channel) }
}
