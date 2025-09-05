import Foundation

// MARK: - Debug Helper
private func debugPrint(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

/// Manages secure configuration and API keys for the app
/// This replaces hardcoded values in plist files with environment-based configuration
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private init() {}
    
    // MARK: - Configuration Keys (Only what's actually used)
    private enum ConfigKey: String {
        case googleClientId = "GOOGLE_CLIENT_ID"
        case googleReversedClientId = "GOOGLE_REVERSED_CLIENT_ID"
        // Note: API_KEY, PROJECT_ID, STORAGE_BUCKET, etc. removed - not used for Calendar/Tasks API
    }
    
    // MARK: - Public Configuration Properties
    var googleClientId: String {
        return getConfigValue(for: .googleClientId) ?? ""
    }
    
    var googleReversedClientId: String {
        return getConfigValue(for: .googleReversedClientId) ?? ""
    }
    
    // Removed unused Firestore/Firebase properties:
    // - googleApiKey (not used for Calendar/Tasks API)
    // - googleProjectId (not used)
    // - googleAppId (not used) 
    // - gcmSenderId (not used)
    // - storageUrl (not used)
    
    // MARK: - Environment Detection
    var isProduction: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
    
    var environment: String {
        return isProduction ? "production" : "development"
    }
    
    // MARK: - Private Methods
    private func getConfigValue(for key: ConfigKey) -> String? {
        // First try to get from environment variables (for CI/CD)
        if let envValue = ProcessInfo.processInfo.environment[key.rawValue], !envValue.isEmpty {
            return envValue
        }
        
        // Fallback to reading directly from Info.plist
        return getValueFromInfoPlist(key: key.rawValue)
    }
    
    private func getValueFromInfoPlist(key: String) -> String? {
        // Map our config keys to actual Info.plist keys
        let infoPlistKey: String
        switch key {
        case "GOOGLE_CLIENT_ID":
            infoPlistKey = "GIDClientID"
        case "GOOGLE_REVERSED_CLIENT_ID":
            infoPlistKey = "CFBundleURLSchemes" // We'll extract from URL schemes
        default:
            infoPlistKey = key
        }
        
        if infoPlistKey == "CFBundleURLSchemes" {
            // Extract reversed client ID from URL schemes array
            if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] {
                for urlType in urlTypes {
                    if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                        for scheme in schemes {
                            if scheme.contains("googleusercontent.apps") {
                                return scheme
                            }
                        }
                    }
                }
            }
            return nil
        } else {
            return Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        }
    }
    
    // MARK: - Validation
    func validateConfiguration() -> Bool {
        let requiredConfigs = [
            ("Google Client ID", googleClientId)
            // Note: Only Client ID is required for Google Sign-In + Calendar/Tasks API
            // API Key, Project ID, etc. are Firestore leftovers and not needed
        ]
        
        var isValid = true
        
        for (name, value) in requiredConfigs {
            if value.isEmpty || value.contains("YOUR_") || value.contains("_HERE") {
                isValid = false
            }
        }
        
        if isValid {
        } else {
        }
        
        return isValid
    }
    
    // MARK: - Debug Information
    func debugPrintConfigurationInfo() {
        #if DEBUG
        debugPrint("🔧 Configuration Manager Status:")
        debugPrint("Environment: \(environment)")
        debugPrint("Google Client ID configured: \(!googleClientId.isEmpty)")
        debugPrint("Google Reversed Client ID configured: \(!googleReversedClientId.isEmpty)")
        debugPrint("Validation passes: \(validateConfiguration())")
        #endif
    }
}
