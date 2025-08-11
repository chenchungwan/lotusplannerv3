import Foundation
import SwiftUI

class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private let maxDataSize = 1_000 // 1KB limit per key for iCloud key-value store
private let maxTotalSize = 1_000_000 // 1MB total limit for all keys
    
    @Published var iCloudAvailable: Bool = false
    @Published var lastSyncDate: Date?
    
    private init() {
        setupiCloudNotifications()
        setupAppLifecycleNotifications()
        checkiCloudAvailability()
        
        // Automatically sync on init
        if iCloudAvailable {
            synchronizeFromiCloud()
        }
    }
    
    private func setupAppLifecycleNotifications() {
        // Sync when app becomes active (important for cross-device sync)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeFromiCloud()
        }
    }
    
    // MARK: - iCloud Setup
    private func setupiCloudNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleiCloudDataChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: keyValueStore
        )
    }
    
    private func checkiCloudAvailability() {
        if let token = FileManager.default.ubiquityIdentityToken {
            iCloudAvailable = true
            print("✅ iCloud is available - Token: \(token)")
            
            // Check if we're in simulator
            #if targetEnvironment(simulator)
            print("📱 Running in simulator - iCloud KV Store may not sync reliably")
            #endif
            
        } else {
            iCloudAvailable = false
            print("❌ iCloud is not available - User not signed in or disabled")
        }
        
        // Test iCloud Key-Value Store access
        print("🔍 Testing iCloud Key-Value Store...")
        keyValueStore.synchronize()
        
        // Get all current keys
        let allKeys = keyValueStore.dictionaryRepresentation.keys
        print("📋 Current iCloud KV Store keys: \(Array(allKeys))")
        
        let testValue = keyValueStore.string(forKey: "icloud_test")
        print("🔍 iCloud KV Store test value: \(testValue ?? "nil")")
        
        // Set a test value to verify write access
        let timestamp = Date().timeIntervalSince1970
        let testString = "test_\(timestamp)"
        keyValueStore.set(testString, forKey: "icloud_test")
        
        // Force immediate sync
        let success = keyValueStore.synchronize()
        print("🔧 Set test value '\(testString)' - sync result: \(success)")
        
        // Try to read it back immediately
        let readBack = keyValueStore.string(forKey: "icloud_test")
        print("🔄 Read back value: \(readBack ?? "nil")")
        
        if readBack == testString {
            print("✅ iCloud KV Store read/write test PASSED")
        } else {
            print("❌ iCloud KV Store read/write test FAILED")
        }
    }
    
    @objc private func handleiCloudDataChanged(_ notification: Notification) {
        print("🔄 iCloud data changed externally")
        Task { @MainActor in
            NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            lastSyncDate = Date()
        }
    }
    
    // MARK: - Generic Data Methods
    func saveDataToiCloud<T: Codable>(data: T, key: String) {
        do {
            let jsonData = try JSONEncoder().encode(data)
            
            // Always save to UserDefaults as backup
            UserDefaults.standard.set(jsonData, forKey: key)
            UserDefaults.standard.synchronize()
            print("💾 Saved \(jsonData.count) bytes to UserDefaults for key: \(key)")
            
            // Check data size - if too large, use chunking strategy
            if jsonData.count > maxDataSize {
                print("⚠️ Data too large for iCloud KV store (\(jsonData.count) bytes > \(maxDataSize) bytes)")
                print("📊 This explains why cross-device sync wasn't working!")
                print("💡 Consider implementing data chunking or using different sync method")
                return
            } else {
                print("✅ Data size OK for iCloud: \(jsonData.count) bytes <= \(maxDataSize) bytes")
            }
            
            // Also save to iCloud if available
            if iCloudAvailable {
                print("🔄 Attempting to save to iCloud for key: \(key)")
                
                // Check if key-value store is actually accessible
                let kvStoreIdentifier = FileManager.default.ubiquityIdentityToken
                print("🔍 iCloud identity token: \(kvStoreIdentifier != nil ? "present" : "missing")")
                
                keyValueStore.set(jsonData, forKey: key)
                
                let syncSuccess = keyValueStore.synchronize()
                print("☁️ iCloud save attempt - sync result: \(syncSuccess)")
                
                if !syncSuccess {
                    print("❌ iCloud sync returned false - possible reasons:")
                    print("   • iCloud Key-Value Store not enabled in App Store Connect")
                    print("   • App not properly signed with iCloud entitlements")
                    print("   • iCloud account has issues")
                    print("   • Network connectivity problems")
                    
                    // Check app's bundle ID and team ID
                    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
                    print("📋 App bundle ID: \(bundleId)")
                    
                    // Check if running in simulator
                    #if targetEnvironment(simulator)
                    print("📱 Running in simulator - this may be the issue")
                    print("💡 Try testing on a real device with same iCloud account")
                    #endif
                }
                
                // Verify the save by reading it back
                if let readBack = keyValueStore.data(forKey: key) {
                    print("✅ Verified: \(readBack.count) bytes saved to iCloud for key: \(key)")
                } else {
                    print("❌ Failed to verify iCloud save for key: \(key)")
                    print("🔍 This confirms iCloud Key-Value Store is not working")
                }
                
                // List all keys after save
                let allKeys = keyValueStore.dictionaryRepresentation.keys
                print("📋 iCloud keys after save: \(Array(allKeys))")
                
                if allKeys.isEmpty {
                    print("⚠️ No keys in iCloud KV Store - this indicates a configuration problem")
                    print("💡 IMMEDIATE SOLUTION: App will use UserDefaults-only mode")
                    print("📱 Data will persist locally but won't sync across devices until iCloud is fixed")
                    print("")
                    print("🔧 To fix cross-device sync:")
                    print("   1. Test on real device (most common fix)")
                    print("   2. Enable Key-Value Store in App Store Connect")
                    print("   3. Check iCloud account settings")
                    print("   4. Verify app signing with correct provisioning profile")
                    
                    // NOTE: Not disabling iCloud here as it might affect data saves
                    print("💾 Continuing to save to UserDefaults for local persistence")
                }
                
            } else {
                print("📱 iCloud unavailable, using UserDefaults only for key: \(key)")
            }
        } catch {
            print("❌ Failed to encode data for key \(key): \(error)")
        }
    }
    
    func loadDataFromiCloud<T: Codable>(key: String, type: T.Type) -> T? {
        var iCloudData: Data?
        var localData: Data?
        
        // Get data from both sources
        if iCloudAvailable {
            iCloudData = keyValueStore.data(forKey: key)
            if let data = iCloudData {
                print("☁️ Found \(data.count) bytes in iCloud for key: \(key)")
            } else {
                print("☁️ No data in iCloud for key: \(key)")
            }
        } else {
            print("❌ iCloud not available for key: \(key)")
        }
        
        localData = UserDefaults.standard.data(forKey: key)
        if let data = localData {
            print("💾 Found \(data.count) bytes in UserDefaults for key: \(key)")
        } else {
            print("💾 No data in UserDefaults for key: \(key)")
        }
        
        // Choose the most recent or merge if both exist
        var selectedData: Data?
        var dataSource = ""
        
        if let icloud = iCloudData, let local = localData {
            // Both exist - for now, prefer iCloud (could implement merge logic later)
            selectedData = icloud
            dataSource = "iCloud (both available)"
            print("🔄 Both sources available, using iCloud data for key: \(key)")
        } else if let icloud = iCloudData {
            selectedData = icloud
            dataSource = "iCloud only"
        } else if let local = localData {
            selectedData = local
            dataSource = "UserDefaults only"
        }
        
        guard let data = selectedData else {
            print("📭 No data found anywhere for key: \(key)")
            return nil
        }
        
        do {
            let decodedData = try JSONDecoder().decode(type, from: data)
            print("✅ Successfully decoded data from \(dataSource) for key: \(key)")
            return decodedData
        } catch {
            print("❌ Failed to decode data from \(dataSource) for key \(key): \(error)")
            return nil
        }
    }
    
    // MARK: - Specific Data Methods
    func saveWeightEntries(_ entries: [WeightLogEntry]) {
        saveDataToiCloud(data: entries, key: "weightEntries")
    }
    
    func loadWeightEntries() -> [WeightLogEntry] {
        return loadDataFromiCloud(key: "weightEntries", type: [WeightLogEntry].self) ?? []
    }
    
    func saveWorkoutEntries(_ entries: [WorkoutLogEntry]) {
        saveDataToiCloud(data: entries, key: "workoutEntries")
    }
    
    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        return loadDataFromiCloud(key: "workoutEntries", type: [WorkoutLogEntry].self) ?? []
    }
    
    func saveFoodEntries(_ entries: [FoodLogEntry]) {
        print("💾 Saving \(entries.count) food entries...")
        do {
            let jsonData = try JSONEncoder().encode(entries)
            print("📊 Food entries data size: \(jsonData.count) bytes")
            
            if jsonData.count > maxDataSize {
                print("⚠️ Food entries too large for iCloud KV store, saving locally only")
                UserDefaults.standard.set(jsonData, forKey: "foodEntries")
                return
            }
            
            saveDataToiCloud(data: entries, key: "foodEntries")
            print("✅ Successfully saved food entries")
        } catch {
            print("❌ Failed to save food entries: \(error)")
        }
    }
    
    func loadFoodEntries() -> [FoodLogEntry] {
        return loadDataFromiCloud(key: "foodEntries", type: [FoodLogEntry].self) ?? []
    }
    

    
    // MARK: - Sync Methods
    func synchronizeFromiCloud() {
        if iCloudAvailable {
            keyValueStore.synchronize()
            print("🔄 Synchronized from iCloud")
            
            // List all keys in iCloud KV Store for debugging
            let allKeys = keyValueStore.dictionaryRepresentation.keys
            print("🔍 iCloud KV Store keys: \(Array(allKeys))")
            
            Task { @MainActor in
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                lastSyncDate = Date()
            }
        } else {
            print("❌ Cannot sync - iCloud not available")
        }
    }
    
    func forceSyncToiCloud() {
        if iCloudAvailable {
            keyValueStore.synchronize()
            print("⬆️ Force synced to iCloud")
            Task { @MainActor in
                lastSyncDate = Date()
            }
        }
    }
    
    // Force a complete bi-directional sync
    func forceCompleteSync() {
        print("🔄 Starting complete bi-directional sync...")
        
        if iCloudAvailable {
            // List what we have before sync
            let keysBefore = keyValueStore.dictionaryRepresentation.keys
            print("📋 Keys before sync: \(Array(keysBefore))")
            
            // First, sync from iCloud
            let syncSuccess = keyValueStore.synchronize()
            print("📥 Pulled from iCloud - success: \(syncSuccess)")
            
            // List what we have after sync
            let keysAfter = keyValueStore.dictionaryRepresentation.keys
            print("📋 Keys after sync: \(Array(keysAfter))")
            
            // Wait a moment for sync to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Notify that data may have changed
                Task { @MainActor in
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                    self.lastSyncDate = Date()
                }
                print("✅ Complete sync finished")
            }
        } else {
            print("❌ Cannot perform complete sync - iCloud not available")
        }
    }
    
    // Diagnostic method to check iCloud configuration
    func diagnoseICloudSetup() {
        print("🔍 Diagnosing iCloud setup...")
        
        // Check iCloud account status
        if let token = FileManager.default.ubiquityIdentityToken {
            print("✅ iCloud account signed in - Token: \(token)")
        } else {
            print("❌ iCloud account not signed in or iCloud disabled")
            return
        }
        
        // Check app's iCloud container access
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            print("✅ iCloud container accessible: \(containerURL)")
        } else {
            print("❌ iCloud container not accessible")
        }
        
        // Test Key-Value Store
        print("🔍 Testing Key-Value Store...")
        let testKey = "diagnostic_test_\(Date().timeIntervalSince1970)"
        let testValue = "test_data"
        
        keyValueStore.set(testValue, forKey: testKey)
        let syncResult = keyValueStore.synchronize()
        print("📤 Test save sync result: \(syncResult)")
        
        let readBack = keyValueStore.string(forKey: testKey)
        print("📥 Test read back: \(readBack ?? "nil")")
        
        if readBack == testValue {
            print("✅ iCloud Key-Value Store is working")
        } else {
            print("❌ iCloud Key-Value Store is NOT working")
        }
        
        // Clean up test key
        keyValueStore.removeObject(forKey: testKey)
        keyValueStore.synchronize()
        
        // Additional checks
        print("🔍 Additional diagnostics:")
        
        // Check if we're in simulator
        #if targetEnvironment(simulator)
        print("📱 Running in iOS Simulator")
        print("⚠️ iCloud Key-Value Store often doesn't work in simulator")
        print("💡 Test on real device for accurate iCloud functionality")
        #else
        print("📱 Running on real device")
        #endif
        
        // Check account status
        if let accountStatus = try? FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            print("✅ iCloud container URL accessible: \(accountStatus)")
        } else {
            print("❌ Cannot access iCloud container")
        }
        
        // Check bundle identifier
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        print("📋 Bundle identifier: \(bundleId)")
        
        // Check if Key-Value Store quota
        let kvData = keyValueStore.dictionaryRepresentation
        let totalSize = kvData.values.compactMap { $0 as? Data }.reduce(0) { $0 + $1.count }
        print("📊 Current iCloud KV Store usage: \(totalSize) bytes / 1MB limit")
        
        // Specific fix recommendations
        print("\n🔧 SPECIFIC FIXES FOR YOUR APP:")
        print("Bundle ID: com.chenchungwan.LotusPlannerV3")
        print("")
        print("1. 📱 IMMEDIATE TEST: Try on real device (not simulator)")
        print("   • Install app on iPhone/iPad with same iCloud account")
        print("   • Simulators often can't access iCloud Key-Value Store")
        print("")
        print("2. 🏪 APP STORE CONNECT: Enable Key-Value Store")
        print("   • Go to developer.apple.com → App Store Connect")
        print("   • Find your app: LotusPlannerV3")
        print("   • Features → iCloud → Enable 'Key-Value Storage'")
        print("   • Wait 15-30 minutes for changes to propagate")
        print("")
        print("3. 🔑 XCODE PROJECT: Verify iCloud capability")
        print("   • Target → Signing & Capabilities → iCloud")
        print("   • Ensure 'Key-value storage' is checked")
        print("   • Clean Build Folder and rebuild")
        print("")
        print("4. 👥 DEVELOPMENT TEAM: Check signing")
        print("   • Ensure you have proper Apple Developer Program access")
        print("   • Verify team ID matches in entitlements")
        
        // Try to get team identifier
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let profileData = NSData(contentsOfFile: path) {
            print("✅ Found provisioning profile")
        } else {
            print("⚠️ No provisioning profile found (normal for simulator)")
        }
    }
    
    func migrateLocalDataToiCloud() {
        print("🔄 Migrating local data to iCloud...")
        
        // Migrate each data type
        let localKeys = ["weightEntries", "workoutEntries", "foodEntries"]
        
        for key in localKeys {
            if let localData = UserDefaults.standard.data(forKey: key) {
                if iCloudAvailable {
                    keyValueStore.set(localData, forKey: key)
                    print("✅ Migrated \(key) to iCloud")
                }
            }
        }
        
        if iCloudAvailable {
            keyValueStore.synchronize()
            print("🔄 Migration sync complete")
        }
    }
    
    func clearAllCloudData() {
        let keys = ["weightEntries", "workoutEntries", "foodEntries"]
        
        for key in keys {
            if iCloudAvailable {
                keyValueStore.removeObject(forKey: key)
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        if iCloudAvailable {
            keyValueStore.synchronize()
        }
        
        print("🗑️ Cleared all cloud and local data")
    }
    
    // MARK: - Storage Status
    func getStorageStatus() -> String {
        if iCloudAvailable {
            return "iCloud Available"
        } else {
            return "Local Storage Only"
        }
    }
    
    func getCurrentStorageUsage() -> String {
        let keys = ["weightEntries", "workoutEntries", "foodEntries"]
        var totalSize = 0
        
        for key in keys {
            if let data = keyValueStore.data(forKey: key) {
                totalSize += data.count
            } else if let data = UserDefaults.standard.data(forKey: key) {
                totalSize += data.count
            }
        }
        
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: Int64(totalSize))
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
} 