import Foundation

/// Manages secure configuration and API keys for the app
/// This replaces hardcoded values in plist files with environment-based configuration
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private init() {}
    
    // MARK: - Configuration Keys
    private enum ConfigKey: String {
        case googleClientId = "GOOGLE_CLIENT_ID"
        case googleReversedClientId = "GOOGLE_REVERSED_CLIENT_ID"
        case googleApiKey = "GOOGLE_API_KEY"
        case googleProjectId = "GOOGLE_PROJECT_ID"
        case googleAppId = "GOOGLE_APP_ID"
        case gcmSenderId = "GCM_SENDER_ID"
        case storageUrl = "GOOGLE_STORAGE_BUCKET"
    }
    
    // MARK: - Public Configuration Properties
    var googleClientId: String {
        return getConfigValue(for: .googleClientId) ?? ""
    }
    
    var googleReversedClientId: String {
        return getConfigValue(for: .googleReversedClientId) ?? ""
    }
    
    var googleApiKey: String {
        return getConfigValue(for: .googleApiKey) ?? ""
    }
    
    var googleProjectId: String {
        return getConfigValue(for: .googleProjectId) ?? ""
    }
    
    var googleAppId: String {
        return getConfigValue(for: .googleAppId) ?? ""
    }
    
    var gcmSenderId: String {
        return getConfigValue(for: .gcmSenderId) ?? ""
    }
    
    var storageUrl: String {
        return getConfigValue(for: .storageUrl) ?? ""
    }
    
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
        
        // Then try to get from a secure config file (if it exists)
        if let configValue = getValueFromConfigFile(key: key.rawValue) {
            return configValue
        }
        
        // For development, we'll use the existing values as fallback
        // In production, these should be replaced with secure environment variables
        return nil
    }
    
    private func getValueFromConfigFile(key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            print("⚠️ GoogleService-Info.plist not found - using fallback values")
            return nil
        }
        
        return plist[key] as? String
    }
    
    // MARK: - Validation
    func validateConfiguration() -> Bool {
        let requiredConfigs = [
            ("Google Client ID", googleClientId),
            ("Google API Key", googleApiKey),
            ("Google Project ID", googleProjectId)
        ]
        
        var isValid = true
        
        for (name, value) in requiredConfigs {
            if value.isEmpty || value.contains("YOUR_") || value.contains("_HERE") {
                print("❌ Invalid configuration for \(name): \(value)")
                isValid = false
            }
        }
        
        if isValid {
            print("✅ Configuration validation passed")
        } else {
            print("❌ Configuration validation failed - check your environment variables or config files")
        }
        
        return isValid
    }
    
    // MARK: - Debug Information
    func printConfigurationInfo() {
        print("📱 App Configuration:")
        print("   Environment: \(environment)")
        print("   Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("   Google Project: \(googleProjectId)")
        print("   Config Valid: \(validateConfiguration())")
    }
}
