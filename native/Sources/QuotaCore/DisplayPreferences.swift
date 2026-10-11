import Foundation

public enum CodexDisplayLanguage: String, Equatable, Sendable {
    case simplifiedChinese
    case traditionalChinese
    case english
}

public enum CodexInterfaceTheme: String, Equatable, Sendable {
    case light, dark
}

public enum CodexLanguageResolver {
    public static func map(_ localeIdentifier: String) -> CodexDisplayLanguage {
        let normalized = localeIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let components = normalized.split(separator: "-").map(String.init)

        guard components.first == "zh" else {
            return .english
        }
        if components.contains("hant") {
            return .traditionalChinese
        }
        if components.contains("hans") {
            return .simplifiedChinese
        }
        if components.contains(where: { ["tw", "hk", "mo"].contains($0) }) {
            return .traditionalChinese
        }
        return .simplifiedChinese
    }

}
