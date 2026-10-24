import Foundation

/// File ownership is separate from platform legacy preferences and secure credentials.
public final class NotificationPolicyStore {
    private let url: URL
    public private(set) var corrupted = false
    public init(url: URL) { self.url = url }
    public func loadOrMigrate(legacy: LegacyNotificationPreferences) throws -> NotificationPolicyPreferences {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            do {
                let value = try JSONDecoder().decode(NotificationPolicyPreferences.self, from: data)
                // Safe decoding intentionally does not overwrite unknown/corrupt evidence.
                corrupted = value.recoveredInvalidData
                return value
            } catch {
                corrupted = true
                var safe = NotificationPolicyPreferences(); safe.enabledChannels = []; safe.rules = [:]
                return safe
            }
        }
        let migrated = NotificationPolicyMigration.migrate(legacy: legacy)
        try save(migrated)
        return migrated
    }
    public func save(_ value: NotificationPolicyPreferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        corrupted = false
    }
}
