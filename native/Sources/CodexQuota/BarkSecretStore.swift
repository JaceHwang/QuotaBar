import Foundation
import Security
import LocalAuthentication

@MainActor protocol BarkSecretStore: AnyObject {
    func read() throws -> String?
    func readForDelivery() async throws -> String?
    func save(_ key: String) throws
    func clear() throws
}
extension BarkSecretStore {
    func readForDelivery() async throws -> String? { try read() }
}
enum BarkSecretError: Error { case unavailable }

/// Accessed only by the explicitly installed application backend, never by view fixtures.
@MainActor final class KeychainBarkSecretStore: BarkSecretStore {
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "QuotaBar.Bark", kSecAttrAccount as String: "device-key"]
    func read() throws -> String? { try Self.readKey() }
    func readForDelivery() async throws -> String? {
        try await Task.detached(priority: .utility) { try Self.readKey() }.value
    }
    nonisolated private static func readKey() throws -> String? {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "QuotaBar.Bark", kSecAttrAccount as String: "device-key"]; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw BarkSecretError.unavailable }
        return key
    }
    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw BarkSecretError.unavailable }
        } else if status != errSecSuccess { throw BarkSecretError.unavailable }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BarkSecretError.unavailable }
    }
}
