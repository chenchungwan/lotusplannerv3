import Foundation
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Singleton responsible for linking/unlinking Google accounts (Personal & Professional).
/// This sample shows the flow with GoogleSignIn SDK but gracefully degrades to a stub
/// if the library isn't added yet so the app continues to compile.
final class GoogleAuthManager: ObservableObject {
    enum AccountKind: String { case personal, professional }

    static let shared = GoogleAuthManager()
    private init() {
        // Migrate from UserDefaults to Keychain on first launch
        migrateToKeychainIfNeeded()
        updateStates()
    }

    // Persist refresh tokens securely using Keychain
    private let tokenKeyPrefix = "google_token_"
    private let accessTokenKeyPrefix = "google_access_token_"
    private let tokenExpiryKeyPrefix = "google_token_expiry_"
    private let emailKeyPrefix = "google_email_"
    private let customNameKeyPrefix = "google_custom_name_"
    
    // Keychain manager for secure token storage
    private let keychainManager = KeychainManager.shared

    // Published map to drive UI updates
    @Published private(set) var linkedStates: [AccountKind: Bool] = [:]
    @Published private(set) var accountEmails: [AccountKind: String] = [:]
    @Published private(set) var customAccountNames: [AccountKind: String] = [:]

    func isLinked(kind: AccountKind) -> Bool {
        linkedStates[kind] ?? false
    }
    
    func getEmail(for kind: AccountKind) -> String {
        return accountEmails[kind] ?? ""
    }
    
    func getCustomName(for kind: AccountKind) -> String {
        return customAccountNames[kind] ?? defaultName(for: kind)
    }
    
    func setCustomName(_ name: String, for kind: AccountKind) {
        let trimmedName = String(name.prefix(25)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        UserDefaults.standard.set(trimmedName, forKey: customNameKeyPrefix + kind.rawValue)
        updateStates()
    }
    
    // MARK: - Secure Token Storage
    private func saveTokenSecurely(_ token: String, for key: String) {
        do {
            try keychainManager.saveString(token, for: key)
        } catch {
            print("❌ Failed to save token to keychain: \(error)")
            // Fallback to UserDefaults for development (should be removed in production)
            #if DEBUG
            UserDefaults.standard.set(token, forKey: key)
            print("⚠️ Falling back to UserDefaults for token storage (DEBUG only)")
            #endif
        }
    }
    
    private func loadTokenSecurely(for key: String) -> String? {
        do {
            return try keychainManager.loadString(for: key)
        } catch KeychainManager.KeychainError.itemNotFound {
            // Check UserDefaults for migration
            if let userDefaultsValue = UserDefaults.standard.string(forKey: key) {
                print("🔄 Found token in UserDefaults, migrating to keychain...")
                saveTokenSecurely(userDefaultsValue, for: key)
                UserDefaults.standard.removeObject(forKey: key)
                return userDefaultsValue
            }
            return nil
        } catch {
            print("❌ Failed to load token from keychain: \(error)")
            return nil
        }
    }
    
    private func deleteTokenSecurely(for key: String) {
        do {
            try keychainManager.delete(for: key)
        } catch {
            print("❌ Failed to delete token from keychain: \(error)")
        }
        // Also remove from UserDefaults as cleanup
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    private func migrateToKeychainIfNeeded() {
        let migrationKey = "keychain_migration_completed"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return // Migration already completed
        }
        
        print("🔄 Starting migration from UserDefaults to Keychain...")
        keychainManager.migrateFromUserDefaults()
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Migration to Keychain completed")
    }

    private func defaultName(for kind: AccountKind) -> String {
        switch kind {
        case .personal: return "Personal"
        case .professional: return "Professional"
        }
    }

    // MARK: - Public API
    @MainActor
    func link(kind: AccountKind, presenting viewController: UIViewController?) async throws {
        print("🔍 Starting link process for \(kind) account")
        
        #if canImport(GoogleSignIn)
        print("✅ GoogleSignIn framework is available")
        
        // Debug: Print all Info.plist keys
        if let infoDict = Bundle.main.infoDictionary {
            print("📋 Info.plist keys: \(infoDict.keys.sorted())")
        } else {
            print("❌ No infoDictionary found")
        }
        
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            print("❌ GIDClientID not found in Info.plist")
            throw AuthError.missingClientID
        }
        print("✅ Found GIDClientID: \(clientID)")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        // Request access to Google Calendar and Tasks
        let scopes = [
            "https://www.googleapis.com/auth/calendar",             // read-write calendar
            "https://www.googleapis.com/auth/tasks"                 // read-write tasks
        ]
        print("🔐 Requesting scopes: \(scopes)")

        let presentingVC: UIViewController = viewController ?? topViewController()!
        print("🎯 Using presenting VC: \(type(of: presentingVC))")
        
        print("🚀 Initiating GoogleSignIn...")
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingVC,
                hint: nil,
                additionalScopes: scopes
            )
            print("✅ Google sign-in completed successfully")
            
            // Store refresh token securely
            let refreshToken = result.user.refreshToken.tokenString
            print("🔑 Storing refresh token for \(kind): \(refreshToken.prefix(20))...")
            saveTokenSecurely(refreshToken, for: tokenKeyPrefix + kind.rawValue)
            
            // Store access token and expiry securely
            let accessToken = result.user.accessToken.tokenString
            let expirationDate = result.user.accessToken.expirationDate
            saveTokenSecurely(accessToken, for: accessTokenKeyPrefix + kind.rawValue)
            UserDefaults.standard.set(expirationDate, forKey: tokenExpiryKeyPrefix + kind.rawValue)
            print("🔑 Stored access token for \(kind), expires: \(String(describing: expirationDate))")
            
            // Store user email
            let userEmail = result.user.profile?.email ?? "Unknown"
            UserDefaults.standard.set(userEmail, forKey: emailKeyPrefix + kind.rawValue)
            print("📧 Stored email for \(kind): \(userEmail)")
            
            updateStates()
        } catch {
            print("❌ Google sign-in failed with error: \(error)")
            
            // Handle keychain errors specifically
            if let nsError = error as NSError?, 
               nsError.domain == "com.google.GIDSignIn" && nsError.code == -2 {
                print("🔑 Keychain error detected - clearing auth state and retrying may help")
                clearAllAuthState()
            }
            
            throw error
        }
        #else
        print("⚠️ GoogleSignIn framework NOT available - using stub")
        // Stub – simulate success
        saveTokenSecurely(UUID().uuidString, for: tokenKeyPrefix + kind.rawValue)
        updateStates()
        #endif
        print("🏁 Link process completed for \(kind)")
    }

    func unlink(kind: AccountKind) {
        #if canImport(GoogleSignIn)
        if let token = UserDefaults.standard.string(forKey: tokenKeyPrefix + kind.rawValue) {
            // Revoke token if needed using Google REST API … skipped for brevity.
            print("Revoking token: \(token)")
        }
        // Clear any Google Sign-In keychain items that might be causing conflicts
        clearGoogleKeychainItems()
        #endif
        deleteTokenSecurely(for: tokenKeyPrefix + kind.rawValue)
        deleteTokenSecurely(for: accessTokenKeyPrefix + kind.rawValue)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKeyPrefix + kind.rawValue)
        UserDefaults.standard.removeObject(forKey: emailKeyPrefix + kind.rawValue)
        UserDefaults.standard.removeObject(forKey: customNameKeyPrefix + kind.rawValue)
        updateStates()
    }
    
    // MARK: - Keychain Cleanup
    private func clearGoogleKeychainItems() {
        #if canImport(GoogleSignIn)
        // This helps resolve keychain conflicts
        GIDSignIn.sharedInstance.signOut()
        #endif
    }
    
    // Public method to force-clear all auth state when keychain errors occur
    func clearAllAuthState() {
        print("🧹 Clearing all Google authentication state due to keychain errors")
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        // Clear keychain items
        keychainManager.clearAllItems()
        // Also clear UserDefaults as backup
        unlink(kind: .personal)
        unlink(kind: .professional)
    }
    
    // MARK: - Access Token Management
    func getAccessToken(for kind: AccountKind) async throws -> String {
        print("🔑 Getting access token for \(kind) account...")
        print("  📊 Account linked status: \(linkedStates[kind] ?? false)")
        print("  📧 Account email: \(accountEmails[kind] ?? "Unknown")")
        
        let accessTokenKey = accessTokenKeyPrefix + kind.rawValue
        let expiryKey = tokenExpiryKeyPrefix + kind.rawValue
        let refreshTokenKey = tokenKeyPrefix + kind.rawValue
        
        // Check if we have a valid access token
        if let accessToken = loadTokenSecurely(for: accessTokenKey),
           let expiryDate = UserDefaults.standard.object(forKey: expiryKey) as? Date,
           expiryDate > Date().addingTimeInterval(60) { // 1 minute buffer
            print("✅ Using cached access token for \(kind), expires: \(expiryDate)")
            return accessToken
        }
        
        print("🔄 Need to refresh access token for \(kind)...")
        
        // Check if we have a refresh token
        guard let refreshToken = loadTokenSecurely(for: refreshTokenKey) else {
            print("❌ No refresh token found for \(kind)")
            print("  🔍 Available UserDefaults keys: \(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("google") })")
            throw AuthError.noRefreshToken
        }
        
        print("🔄 Found refresh token for \(kind): \(refreshToken.prefix(20))...")
        
        // Need to refresh the access token
        #if canImport(GoogleSignIn)
        print("🔄 Refreshing access token for \(kind)...")
        return try await refreshAccessToken(refreshToken: refreshToken, for: kind)
        #else
        // For stub/testing purposes
        print("❌ GoogleSignIn not available")
        throw AuthError.noRefreshToken
        #endif
    }
    
    #if canImport(GoogleSignIn)
    private func refreshAccessToken(refreshToken: String, for kind: AccountKind) async throws -> String {
        print("🔄 Starting token refresh for \(kind)...")
        
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            print("❌ No GIDClientID found in Info.plist")
            throw AuthError.missingClientID
        }
        
        print("🔑 Using client ID: \(clientID)")
        
        // Use Google's OAuth2 endpoint to refresh the token
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        request.httpBody = bodyString.data(using: .utf8)
        
        print("🌐 Making token refresh request for \(kind)...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response from token refresh for \(kind)")
            throw AuthError.tokenRefreshFailed
        }
        
        print("📊 Token refresh response status for \(kind): \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            print("❌ Token refresh failed for \(kind) - Status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Token refresh error response: \(responseString)")
            }
            throw AuthError.tokenRefreshFailed
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
        }
        
        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            // Store the new access token and expiry
            let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
            saveTokenSecurely(tokenResponse.access_token, for: accessTokenKeyPrefix + kind.rawValue)
            UserDefaults.standard.set(expiryDate, forKey: tokenExpiryKeyPrefix + kind.rawValue)
            
            print("✅ Successfully refreshed access token for \(kind), expires: \(expiryDate)")
            
            return tokenResponse.access_token
        } catch {
            print("❌ Failed to decode token response for \(kind): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Raw response: \(responseString)")
            }
            throw AuthError.tokenRefreshFailed
        }
    }
    #endif

    enum AuthError: Error {
        case missingClientID
        case noRefreshToken
        case tokenRefreshFailed
    }

    // MARK: - Helpers
    private func updateStates() {
        linkedStates = [
            .personal: loadTokenSecurely(for: tokenKeyPrefix + AccountKind.personal.rawValue) != nil,
            .professional: loadTokenSecurely(for: tokenKeyPrefix + AccountKind.professional.rawValue) != nil
        ]
        
        accountEmails = [
            .personal: UserDefaults.standard.string(forKey: emailKeyPrefix + AccountKind.personal.rawValue) ?? "",
            .professional: UserDefaults.standard.string(forKey: emailKeyPrefix + AccountKind.professional.rawValue) ?? ""
        ]
        
        customAccountNames = [
            .personal: UserDefaults.standard.string(forKey: customNameKeyPrefix + AccountKind.personal.rawValue) ?? defaultName(for: .personal),
            .professional: UserDefaults.standard.string(forKey: customNameKeyPrefix + AccountKind.professional.rawValue) ?? defaultName(for: .professional)
        ]
    }

    // Traverse windows to find top view controller
    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }.first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        } else if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
} 