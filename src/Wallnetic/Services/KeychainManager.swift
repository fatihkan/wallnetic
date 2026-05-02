import Foundation
import Security

/// Manages secure storage of API keys in the macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.wallnetic.apikeys"

    private init() {}

    // MARK: - Public Methods

    /// Saves an API key for the specified provider
    @discardableResult
    func saveAPIKey(_ apiKey: String, for provider: APIProvider) -> Bool {
        let account = provider.rawValue

        // Delete existing key first
        deleteAPIKey(for: provider)

        guard let data = apiKey.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        #if DEBUG
        if status != errSecSuccess {
            Log.keychain.error("Failed to save API key: \(status)")
        }
        #endif

        return status == errSecSuccess
    }

    /// Retrieves the API key for the specified provider
    func getAPIKey(for provider: APIProvider) -> String? {
        let account = provider.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    /// Deletes the API key for the specified provider
    @discardableResult
    func deleteAPIKey(for provider: APIProvider) -> Bool {
        let account = provider.rawValue

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Checks if an API key exists for the specified provider
    func hasAPIKey(for provider: APIProvider) -> Bool {
        return getAPIKey(for: provider) != nil
    }
}
