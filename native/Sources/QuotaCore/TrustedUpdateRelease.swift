import Foundation

public struct UpdateAsset: Sendable, Equatable, Codable {
    public let name: String
    public let url: URL
    public let size: Int64
    public let sha256: String
}
public struct TrustedUpdateRelease: Sendable, Equatable {
    public let version: String
    public let platform: String
    public let sourceCommit: String
    public let package: UpdateAsset
    public let provenance: UpdateAsset
    public static let repository = "JaceHwang/QuotaBar"
    public static let maxDownloadBytes: Int64 = 512 * 1024 * 1024
    public static func apiURL(version: String) throws -> URL {
        _ = try UpdateFeed.versionParts(version)
        return URL(string: "https://api.github.com/repos/\(repository)/releases/tags/v\(version)")!
    }
    public static func tagURL(version: String) throws -> URL {
        _ = try UpdateFeed.versionParts(version)
        return URL(string: "https://api.github.com/repos/\(repository)/git/ref/tags/v\(version)")!
    }
    public static func allowedDownloadRedirect(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && url.fragment == nil && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host?.lowercased() ?? "")
    }
    public static func parse(releaseJSON: Data, tagJSON: Data, version: String, platform: String, currentVersion: String) throws -> TrustedUpdateRelease {
        func reject() -> CocoaError { CocoaError(.fileReadCorruptFile) }
        guard releaseJSON.count <= 2 * 1024 * 1024, tagJSON.count <= 1024 * 1024,
              try UpdateFeed.versionParts(currentVersion).lexicographicallyPrecedes(UpdateFeed.versionParts(version)) else { throw reject() }
        struct Asset: Decodable { let name: String; let state: String; let size: Int64; let digest: String?; let browser_download_url: String }
        struct Release: Decodable { let tag_name: String; let html_url: String; let draft: Bool; let prerelease: Bool; let assets: [Asset] }
        struct Ref: Decodable { struct Object: Decodable { let type: String; let sha: String }; let object: Object }
        let release = try JSONDecoder().decode(Release.self, from: releaseJSON)
        let tag = try JSONDecoder().decode(Ref.self, from: tagJSON)
        guard release.tag_name == "v" + version, !release.draft, !release.prerelease,
              release.html_url == "https://github.com/\(repository)/releases/tag/v\(version)",
              release.assets.count <= 1000, Set(release.assets.map { $0.name.lowercased() }).count == release.assets.count,
              tag.object.type == "commit", hex(tag.object.sha, count: 40) else { throw reject() }
        let packageName: String, proofName: String
        switch platform {
        case "macos-arm64": packageName = "codex-quota-v\(version)-macos-arm64.dmg"; proofName = "CODEX-QUOTA-PROVENANCE.json"
        case "windows-x64": packageName = "QuotaBar-\(version)-windows-x64.zip"; proofName = "QUOTABAR-WINDOWS-PROVENANCE.json"
        default: throw reject()
        }
        func select(_ name: String, limit: Int64) throws -> UpdateAsset {
            guard let a = release.assets.first(where: { $0.name == name }), a.state == "uploaded", a.size > 0, a.size <= limit,
                  let digest = a.digest, digest.hasPrefix("sha256:"), hex(String(digest.dropFirst(7)), count: 64),
                  a.browser_download_url == "https://github.com/\(repository)/releases/download/v\(version)/\(name)",
                  let url = URL(string: a.browser_download_url) else { throw reject() }
            return UpdateAsset(name: name, url: url, size: a.size, sha256: String(digest.dropFirst(7)))
        }
        return try TrustedUpdateRelease(version: version, platform: platform, sourceCommit: tag.object.sha, package: select(packageName, limit: maxDownloadBytes), provenance: select(proofName, limit: 1024 * 1024))
    }
    public static func hex(_ value: String, count: Int) -> Bool { value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}

public enum ApplicationUpdatePhase: String, Codable, Sendable {
    case idle, resolving, downloading, verifying, preparing, handingOff, installing, succeeded, rolledBack, failed, cancelled
    public var canCancel: Bool { [.resolving, .downloading, .verifying, .preparing].contains(self) }
    public var busy: Bool { canCancel || self == .handingOff || self == .installing }
}
public struct ApplicationUpdateProgress: Sendable, Equatable {
    public let phase: ApplicationUpdatePhase
    public let received: Int64
    public let total: Int64
    public let failure: String?
    public init(_ phase: ApplicationUpdatePhase, received: Int64 = 0, total: Int64 = 0, failure: String? = nil) { self.phase = phase; self.received = received; self.total = total; self.failure = failure }
}
