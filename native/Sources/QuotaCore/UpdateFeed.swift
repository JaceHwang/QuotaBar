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
    public struct Selection: Sendable, Equatable { public let release: UpdateRelease?; public let betaError: Bool }
    public static func select(in data: Data, platform: String, current: String, os: String, allowBeta: Bool) throws -> Selection {
        let stable = try available(in: data, platform: platform, current: current, os: os)
        let installed = try ProductVersion(current)
        guard allowBeta else { return Selection(release: stable, betaError: false) }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            guard let raw = root["beta"] else { return Selection(release: stable, betaError: false) }
            guard let beta = raw as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            guard let candidate = beta[platform] else { return Selection(release: stable, betaError: false) }
            guard JSONSerialization.isValidJSONObject(candidate) else { throw CocoaError(.fileReadCorruptFile) }
            var entry = try JSONDecoder().decode(UpdateRelease.self, from: JSONSerialization.data(withJSONObject: candidate))
            let version = try ProductVersion(entry.version)
            guard version.isBeta,
                  ["QuotaBar", "codex-usage-sidebar"].contains(where: { entry.releaseNotesURL.absoluteString == "https://github.com/JaceHwang/\($0)/releases/tag/v\(entry.version)" }) else { throw CocoaError(.fileReadCorruptFile) }
            let minimum = try versionParts(entry.minOS, os: true)
            guard try !versionParts(os, os: true).lexicographicallyPrecedes(minimum), installed < version else {
                return Selection(release: stable, betaError: false)
            }
            if let stable, try ProductVersion(stable.version) >= version { return Selection(release: stable, betaError: false) }
            entry.summary = entry.summary.map { String($0.prefix(240)) }
            entry.releaseNotes = entry.releaseNotes.map { String($0.prefix(16000)) }
            return Selection(release: entry, betaError: false)
        } catch {
            return Selection(release: stable, betaError: true)
        }
    }
    public static let endpoint = URL(string: "https://jacehwang.github.io/QuotaBar/updates.json")!
    private struct FeedHeader: Decodable { let schemaVersion: Int }
    public static func versionParts(_ value: String, os: Bool = false) throws -> [Int] {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (os ? (2...3).contains(parts.count) : parts.count == 3), parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy({ $0.isASCII && $0.isNumber }) && (part.count == 1 || part.first != "0") && Int(part) != nil
        }) else { throw CocoaError(.fileReadCorruptFile) }
        return parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func available(in data: Data, platform: String, current: String, os: String) throws -> UpdateRelease? {
        guard data.count <= 262144 else { throw CocoaError(.fileReadTooLarge) }
        let header = try JSONDecoder().decode(FeedHeader.self, from: data)
        guard header.schemaVersion == 1,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stable = root["stable"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        guard let raw = stable[platform] else { return nil }
        guard JSONSerialization.isValidJSONObject(raw) else { throw CocoaError(.fileReadCorruptFile) }
        let entry = try JSONDecoder().decode(UpdateRelease.self, from: JSONSerialization.data(withJSONObject: raw))
        let version = try ProductVersion(entry.version)
        guard !version.isBeta else { throw CocoaError(.fileReadCorruptFile) }
        let url = entry.releaseNotesURL
        guard ["QuotaBar", "codex-usage-sidebar"].contains(where: { url.absoluteString == "https://github.com/JaceHwang/\($0)/releases/tag/v\(entry.version)" }) else { throw CocoaError(.fileReadCorruptFile) }
        guard try versionParts(os, os: true).lexicographicallyPrecedes(versionParts(entry.minOS, os: true)) == false,
              try ProductVersion(current) < version else { return nil }
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
