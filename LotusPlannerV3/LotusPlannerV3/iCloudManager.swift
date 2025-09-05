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
            
            // Check if we're in simulator
            #if targetEnvironment(simulator)
            #endif
            
        } else {
            iCloudAvailable = false
        }
        
        // Test iCloud Key-Value Store access
        keyValueStore.synchronize()
        
        // Get all current keys
        let allKeys = keyValueStore.dictionaryRepresentation.keys
        
        let testValue = keyValueStore.string(forKey: "icloud_test")
        
        // Set a test value to verify write access
        let timestamp = Date().timeIntervalSince1970
        let testString = "test_\(timestamp)"
        keyValueStore.set(testString, forKey: "icloud_test")
        
        // Force immediate sync
        let success = keyValueStore.synchronize()
        
        // Try to read it back immediately
        let readBack = keyValueStore.string(forKey: "icloud_test")
        
        if readBack == testString {
        } else {
        }
    }
    
    @objc private func handleiCloudDataChanged(_ notification: Notification) {
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
            
            // Check data size - if too large, use chunking strategy
            if jsonData.count > maxDataSize {
                return
            } else {
            }
            
            // Also save to iCloud if available
            if iCloudAvailable {
                
                // Check if key-value store is actually accessible
                let kvStoreIdentifier = FileManager.default.ubiquityIdentityToken
                
                keyValueStore.set(jsonData, forKey: key)
                
                let syncSuccess = keyValueStore.synchronize()
                
                if !syncSuccess {
                    
                    // Check app's bundle ID and team ID
                    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
                    
                    // Check if running in simulator
                    #if targetEnvironment(simulator)
                    #endif
                }
                
                // Verify the save by reading it back
                if let readBack = keyValueStore.data(forKey: key) {
                } else {
                }
                
                // List all keys after save
                let allKeys = keyValueStore.dictionaryRepresentation.keys
                
                if allKeys.isEmpty {
                    
                    // NOTE: Not disabling iCloud here as it might affect data saves
                }
                
            } else {
            }
        } catch {
        }
    }
    
    func loadDataFromiCloud<T: Codable>(key: String, type: T.Type) -> T? {
        var iCloudData: Data?
        var localData: Data?
        
        // Get data from both sources
        if iCloudAvailable {
            iCloudData = keyValueStore.data(forKey: key)
            if let data = iCloudData {
            } else {
            }
        } else {
        }
        
        localData = UserDefaults.standard.data(forKey: key)
        if let data = localData {
        } else {
        }
        
        // Choose the most recent or merge if both exist
        var selectedData: Data?
        var dataSource = ""
        
        if let icloud = iCloudData, let local = localData {
            // Both exist - for now, prefer iCloud (could implement merge logic later)
            selectedData = icloud
            dataSource = "iCloud (both available)"
        } else if let icloud = iCloudData {
            selectedData = icloud
            dataSource = "iCloud only"
        } else if let local = localData {
            selectedData = local
            dataSource = "UserDefaults only"
        }
        
        guard let data = selectedData else {
            return nil
        }
        
        do {
            let decodedData = try JSONDecoder().decode(type, from: data)
            return decodedData
        } catch {
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
        do {
            let jsonData = try JSONEncoder().encode(entries)
            
            if jsonData.count > maxDataSize {
                UserDefaults.standard.set(jsonData, forKey: "foodEntries")
                return
            }
            
            saveDataToiCloud(data: entries, key: "foodEntries")
        } catch {
        }
    }
    
    func loadFoodEntries() -> [FoodLogEntry] {
        return loadDataFromiCloud(key: "foodEntries", type: [FoodLogEntry].self) ?? []
    }
    

    
    // MARK: - Sync Methods
    func synchronizeFromiCloud() {
        if iCloudAvailable {
            keyValueStore.synchronize()
            
            // List all keys in iCloud KV Store for debugging
            let allKeys = keyValueStore.dictionaryRepresentation.keys
            
            Task { @MainActor in
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                lastSyncDate = Date()
            }
        } else {
        }
    }
    
    func forceSyncToiCloud() {
        if iCloudAvailable {
            keyValueStore.synchronize()
            Task { @MainActor in
                lastSyncDate = Date()
            }
        }
    }
    
    // Force a complete bi-directional sync
    func forceCompleteSync() {
        
        if iCloudAvailable {
            // List what we have before sync
            let keysBefore = keyValueStore.dictionaryRepresentation.keys
            
            // First, sync from iCloud
            let syncSuccess = keyValueStore.synchronize()
            
            // List what we have after sync
            let keysAfter = keyValueStore.dictionaryRepresentation.keys
            
            // Wait a moment for sync to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Notify that data may have changed
                Task { @MainActor in
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                    self.lastSyncDate = Date()
                }
            }
        } else {
        }
    }
    
    // Diagnostic method to check iCloud configuration
    func diagnoseICloudSetup() {
        
        // Check iCloud account status
        if let token = FileManager.default.ubiquityIdentityToken {
        } else {
            return
        }
        
        // Check app's iCloud container access
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
        } else {
        }
        
        // Test Key-Value Store
        let testKey = "diagnostic_test_\(Date().timeIntervalSince1970)"
        let testValue = "test_data"
        
        keyValueStore.set(testValue, forKey: testKey)
        let syncResult = keyValueStore.synchronize()
        
        let readBack = keyValueStore.string(forKey: testKey)
        
        if readBack == testValue {
        } else {
        }
        
        // Clean up test key
        keyValueStore.removeObject(forKey: testKey)
        keyValueStore.synchronize()
        
        // Additional checks
        
        // Check if we're in simulator
        #if targetEnvironment(simulator)
        #else
        #endif
        
        // Check account status
        if let accountStatus = try? FileManager.default.url(forUbiquityContainerIdentifier: nil) {
        } else {
        }
        
        // Check bundle identifier
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        
        // Check if Key-Value Store quota
        let kvData = keyValueStore.dictionaryRepresentation
        let totalSize = kvData.values.compactMap { $0 as? Data }.reduce(0) { $0 + $1.count }
        
        // Specific fix recommendations
        
        // Try to get team identifier
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let profileData = NSData(contentsOfFile: path) {
        } else {
        }
    }
    
    func migrateLocalDataToiCloud() {
        
        // Migrate each data type
        let localKeys = ["weightEntries", "workoutEntries", "foodEntries"]
        
        for key in localKeys {
            if let localData = UserDefaults.standard.data(forKey: key) {
                if iCloudAvailable {
                    keyValueStore.set(localData, forKey: key)
                }
            }
        }
        
        if iCloudAvailable {
            keyValueStore.synchronize()
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