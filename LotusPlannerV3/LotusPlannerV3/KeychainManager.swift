import Foundation
import Security

/// Secure keychain manager for storing sensitive data like tokens and credentials
/// Replaces insecure UserDefaults storage with iOS Keychain Services
class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Keychain Service Identifier
    private let service = Bundle.main.bundleIdentifier ?? "com.chenchungwan.LotusPlannerV3"
    
    // MARK: - Keychain Errors
    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedPasswordData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unexpectedPasswordData:
                return "Unexpected password data"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    // MARK: - Save to Keychain
    func save(_ data: Data, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            break
        case errSecDuplicateItem:
            // Item already exists, try to update it
            try update(data, for: account)
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Load from Keychain
    func load(for account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedPasswordData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Update Keychain Item
    private func update(_ data: Data, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        switch status {
        case errSecSuccess:
            break
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Delete from Keychain
    func delete(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            break
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Convenience Methods for String Storage
    func saveString(_ string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.unexpectedPasswordData
        }
        try save(data, for: account)
    }
    
    func loadString(for account: String) throws -> String {
        let data = try load(for: account)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedPasswordData
        }
        return string
    }
    
    // MARK: - Clear All Keychain Items for this App
    func clearAllItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            break
        default:
            break
        }
    }
    
    // MARK: - Migration from UserDefaults
    func migrateFromUserDefaults() {
        
        let keysToMigrate = [
            "google_token_personal",
            "google_token_professional",
            "google_access_token_personal",
            "google_access_token_professional"
        ]
        
        for key in keysToMigrate {
            if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
                do {
                    try saveString(value, for: key)
                    UserDefaults.standard.removeObject(forKey: key)
                } catch {
                }
            }
        }
        
    }
}
