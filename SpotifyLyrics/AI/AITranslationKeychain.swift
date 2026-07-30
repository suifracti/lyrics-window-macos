import Foundation
import Security

public protocol AITranslationAPIKeyStore: Sendable {
    func read() -> String?
    func save(_ key: String) throws
    func delete() throws
}

public final class KeychainAITranslationAPIKeyStore: AITranslationAPIKeyStore, @unchecked Sendable {
    public static let service = "com.spotifylyrics.ai-translation"
    private let account: String

    public init(account: String = "default") {
        self.account = account
    }

    public func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw AITranslationKeychainError.status(status) }
        } else if updateStatus != errSecSuccess {
            throw AITranslationKeychainError.status(updateStatus)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AITranslationKeychainError.status(status)
        }
    }
}

public enum AITranslationKeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}
