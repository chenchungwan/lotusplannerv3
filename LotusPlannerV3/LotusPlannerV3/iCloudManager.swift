import Foundation
import SwiftUI

class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private let maxDataSize = 100_000 // 100KB limit for key-value store
    
    @Published var iCloudAvailable: Bool = false
    @Published var lastSyncDate: Date?
    
    private init() {
        setupiCloudNotifications()
        checkiCloudAvailability()
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
        if let _ = FileManager.default.ubiquityIdentityToken {
            iCloudAvailable = true
            print("✅ iCloud is available")
        } else {
            iCloudAvailable = false
            print("❌ iCloud is not available")
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
            
            // Check data size - if too large, save locally only
            if jsonData.count > maxDataSize {
                print("⚠️ Data too large for iCloud KV store (\(jsonData.count) bytes), saving locally only")
                UserDefaults.standard.set(jsonData, forKey: key)
                return
            }
            
            if iCloudAvailable {
                keyValueStore.set(jsonData, forKey: key)
                keyValueStore.synchronize()
                print("☁️ Saved \(jsonData.count) bytes to iCloud for key: \(key)")
            } else {
                UserDefaults.standard.set(jsonData, forKey: key)
                print("💾 Saved to local storage (iCloud unavailable) for key: \(key)")
            }
        } catch {
            print("❌ Failed to encode data for key \(key): \(error)")
            // Fallback to UserDefaults
            if let data = data as? Data {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    
    func loadDataFromiCloud<T: Codable>(key: String, type: T.Type) -> T? {
        var jsonData: Data?
        
        // Try iCloud first
        if iCloudAvailable {
            jsonData = keyValueStore.data(forKey: key)
            if jsonData != nil {
                print("☁️ Loaded data from iCloud for key: \(key)")
            }
        }
        
        // Fallback to UserDefaults
        if jsonData == nil {
            jsonData = UserDefaults.standard.data(forKey: key)
            if jsonData != nil {
                print("💾 Loaded data from local storage for key: \(key)")
            }
        }
        
        guard let data = jsonData else {
            print("📭 No data found for key: \(key)")
            return nil
        }
        
        do {
            let decodedData = try JSONDecoder().decode(type, from: data)
            return decodedData
        } catch {
            print("❌ Failed to decode data for key \(key): \(error)")
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
    
    func saveGoals(_ goals: [Goal]) {
        saveDataToiCloud(data: goals, key: "goals")
    }
    
    func loadGoals() -> [Goal] {
        return loadDataFromiCloud(key: "goals", type: [Goal].self) ?? []
    }
    
    func saveCategories(_ categories: [GoalCategory]) {
        saveDataToiCloud(data: categories, key: "categories")
    }
    
    func loadCategories() -> [GoalCategory] {
        return loadDataFromiCloud(key: "categories", type: [GoalCategory].self) ?? []
    }
    
    // MARK: - Sync Methods
    func synchronizeFromiCloud() {
        if iCloudAvailable {
            keyValueStore.synchronize()
            print("🔄 Synchronized from iCloud")
            Task { @MainActor in
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                lastSyncDate = Date()
            }
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
    
    func migrateLocalDataToiCloud() {
        print("🔄 Migrating local data to iCloud...")
        
        // Migrate each data type
        let localKeys = ["weightEntries", "workoutEntries", "foodEntries", "goals", "categories"]
        
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
        let keys = ["weightEntries", "workoutEntries", "foodEntries", "goals", "categories"]
        
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
        let keys = ["weightEntries", "workoutEntries", "foodEntries", "goals", "categories"]
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