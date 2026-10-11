import Foundation

public struct AccountIdentity: Equatable, Sendable {
    public let displayName: String?
    public let email: String?
    public let avatarURL: URL?

    public init(
        displayName: String? = nil,
        email: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
    }

    public var preferredName: String? {
        let candidate = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty {
            return candidate
        }
        let address = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        return address?.isEmpty == false ? address : nil
    }
}

public enum AccountIdentityDecodingError: Error, Equatable, Sendable {
    case invalidJSON
    case missingAccount
}

public enum AccountIdentityDecoder {
    public static func decodeResponse(_ data: Data) throws -> AccountIdentity {
        guard
            let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let account = root["result"] as? [String: Any],
            let accountObject = account["account"] as? [String: Any]
        else {
            throw AccountIdentityDecodingError.invalidJSON
        }

        let profile = accountObject["profile"] as? [String: Any] ?? [:]
        let displayName = firstString(
            in: accountObject,
            keys: ["displayName", "display_name", "name"]
        ) ?? firstString(
            in: profile,
            keys: ["displayName", "display_name", "name"]
        )
        let email = firstString(in: accountObject, keys: ["email"])
            ?? firstString(in: profile, keys: ["email"])
        let avatarString = firstString(
            in: accountObject,
            keys: ["avatarUrl", "avatarURL", "avatar_url", "imageUrl", "image_url"]
        ) ?? firstString(
            in: profile,
            keys: ["avatarUrl", "avatarURL", "avatar_url", "imageUrl", "image_url"]
        )
        let avatarURL = avatarString.flatMap(URL.init(string:))

        guard displayName != nil || email != nil || avatarURL != nil else {
            throw AccountIdentityDecodingError.missingAccount
        }
        return AccountIdentity(
            displayName: displayName,
            email: email,
            avatarURL: avatarURL
        )
    }

    private static func firstString(
        in object: [String: Any],
        keys: [String]
    ) -> String? {
        keys.lazy.compactMap { object[$0] as? String }.first
    }
}
