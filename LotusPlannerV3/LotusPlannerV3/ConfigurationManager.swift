import Foundation

// MARK: - Debug Helper
private func debugPrint(_ message: String) {
    #if DEBUG
    debugPrint(message)
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
        
        // Then try to get from a secure config file (if it exists)
        if let configValue = getValueFromConfigFile(key: key.rawValue) {
            return configValue
        }
        
        // For development, we'll use the existing values as fallback
        // In production, these should be replaced with secure environment variables
        return nil
    }
    
    // GoogleService-Info.plist no longer needed - using Info.plist environment variables
    private func getValueFromConfigFile(key: String) -> String? {
        return nil // Simplified: Only use environment variables or Info.plist
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
    }
}
