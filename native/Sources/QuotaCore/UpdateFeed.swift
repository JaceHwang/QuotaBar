import Foundation

public struct UpdateRelease: Codable, Sendable, Equatable {
    public let version: String
    public let minOS: String
    public let releaseNotesURL: URL
    public var summary: String? = nil
    public var releaseNotes: String? = nil
    public var notificationSummary: String? {
        let value = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : String(value.prefix(240))
    }
}
public enum UpdateFeed {
    public static let endpoint = URL(string: "https://jacehwang.github.io/codex-usage-sidebar/updates.json")!
    private struct Feed: Decodable { let schemaVersion: Int; let stable: [String: UpdateRelease] }
    public static func versionParts(_ value: String, os: Bool = false) throws -> [Int] {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (os ? (2...3).contains(parts.count) : parts.count == 3), parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy({ $0.isASCII && $0.isNumber }) && (part.count == 1 || part.first != "0") && Int(part) != nil
        }) else { throw CocoaError(.fileReadCorruptFile) }
        return parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func available(in data: Data, platform: String, current: String, os: String) throws -> UpdateRelease? {
        guard data.count <= 262144 else { throw CocoaError(.fileReadTooLarge) }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard feed.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        guard let entry = feed.stable[platform] else { return nil }
        let version = try versionParts(entry.version)
        let url = entry.releaseNotesURL
        guard url.absoluteString == "https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v\(entry.version)" else { throw CocoaError(.fileReadCorruptFile) }
        guard try versionParts(os, os: true).lexicographicallyPrecedes(versionParts(entry.minOS, os: true)) == false,
              try versionParts(current).lexicographicallyPrecedes(version) else { return nil }
        var result = entry
        result.summary = entry.summary.map { String($0.prefix(240)) }
        result.releaseNotes = entry.releaseNotes.map { String($0.prefix(16000)) }
        return result
    }
}
public struct UpdateReminderPolicy: Codable, Sendable, Equatable {
    public var notifiedVersion: String?
    public var skippedVersion: String?
    public var snoozeUntil: Date?
    public init() {}
    public mutating func recordNotification(_ version: String, attempted: UpdateReminderPolicy) {
        notifiedVersion = version
        if snoozeUntil == attempted.snoozeUntil { snoozeUntil = nil }
    }
    public func shouldNotify(_ version: String, now: Date) -> Bool {
        guard version != skippedVersion else { return false }
        if let snoozeUntil { return now >= snoozeUntil }
        return version != notifiedVersion
    }
}
