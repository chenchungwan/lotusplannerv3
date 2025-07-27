import Foundation
import Combine

@MainActor
class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private let fileManager = FileManager.default
    private let notificationCenter = NotificationCenter.default
    
    @Published var iCloudAvailable = false
    @Published var isConnectedToInternet = true
    
    // Storage keys for different data types
    private let weightEntriesKey = "icloud_weight_entries"
    private let workoutEntriesKey = "icloud_workout_entries"
    private let foodEntriesKey = "icloud_food_entries"
    private let goalsKey = "icloud_goals"
    private let goalCategoriesKey = "icloud_goal_categories"
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        checkiCloudAvailability()
        setupiCloudNotifications()
        // Sync data from iCloud on startup
        synchronizeFromiCloud()
    }
    
    // MARK: - iCloud Availability
    private func checkiCloudAvailability() {
        if let _ = fileManager.ubiquityIdentityToken {
            iCloudAvailable = true
            print("📱 iCloud is available and user is signed in")
        } else {
            iCloudAvailable = false
            print("❌ iCloud is not available or user is not signed in")
        }
    }
    
    private func setupiCloudNotifications() {
        // Listen for iCloud availability changes
        notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: keyValueStore,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleiCloudDataChanged(notification)
            }
        }
        
        // Start monitoring iCloud sync
        keyValueStore.synchronize()
    }
    
    private func handleiCloudDataChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        print("📡 iCloud data changed, reason: \(reason)")
        
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange:
            print("📥 Syncing data from iCloud server")
            synchronizeFromiCloud()
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            print("🔄 Initial iCloud sync completed")
            synchronizeFromiCloud()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("⚠️ iCloud storage quota exceeded")
        case NSUbiquitousKeyValueStoreAccountChange:
            print("👤 iCloud account changed")
            checkiCloudAvailability()
        default:
            print("❓ Unknown iCloud change reason: \(reason)")
        }
    }
    
    // MARK: - Data Storage Methods
    func saveWeightEntries(_ entries: [WeightLogEntry]) {
        saveDataToiCloud(entries, key: weightEntriesKey, fallbackKey: "stored_weight_entries")
    }
    
    func loadWeightEntries() -> [WeightLogEntry] {
        return loadDataFromiCloud(key: weightEntriesKey, fallbackKey: "stored_weight_entries", type: [WeightLogEntry].self) ?? []
    }
    
    func saveWorkoutEntries(_ entries: [WorkoutLogEntry]) {
        saveDataToiCloud(entries, key: workoutEntriesKey, fallbackKey: "stored_workout_entries")
    }
    
    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        return loadDataFromiCloud(key: workoutEntriesKey, fallbackKey: "stored_workout_entries", type: [WorkoutLogEntry].self) ?? []
    }
    
    func saveFoodEntries(_ entries: [FoodLogEntry]) {
        print("☁️ iCloudManager: Saving \(entries.count) food entries")
        saveDataToiCloud(entries, key: foodEntriesKey, fallbackKey: "stored_food_entries")
    }
    
    func loadFoodEntries() -> [FoodLogEntry] {
        return loadDataFromiCloud(key: foodEntriesKey, fallbackKey: "stored_food_entries", type: [FoodLogEntry].self) ?? []
    }
    
    func saveGoals(_ goals: [Goal]) {
        saveDataToiCloud(goals, key: goalsKey, fallbackKey: "stored_goals")
    }
    
    func loadGoals() -> [Goal] {
        return loadDataFromiCloud(key: goalsKey, fallbackKey: "stored_goals", type: [Goal].self) ?? []
    }
    
    func saveGoalCategories(_ categories: [GoalCategory]) {
        saveDataToiCloud(categories, key: goalCategoriesKey, fallbackKey: "goalCategories")
    }
    
    func loadGoalCategories() -> [GoalCategory] {
        return loadDataFromiCloud(key: goalCategoriesKey, fallbackKey: "goalCategories", type: [GoalCategory].self) ?? []
    }
    
    // MARK: - Generic Storage Methods
    private func saveDataToiCloud<T: Codable>(_ data: T, key: String, fallbackKey: String) {
        do {
            let jsonData = try JSONEncoder().encode(data)
            let dataSize = jsonData.count
            print("📊 Attempting to save \(key): \(dataSize) bytes")
            
            // Check if data size is reasonable for key-value store (max ~100KB per key)
            if dataSize > 100_000 {
                print("⚠️ Data too large for key-value store (\(dataSize) bytes), saving locally only")
                UserDefaults.standard.set(jsonData, forKey: fallbackKey)
                print("💾 Saved \(key) locally (too large for iCloud KV store)")
                return
            }
            
            if iCloudAvailable {
                // Save to iCloud key-value store (for small data only)
                keyValueStore.set(jsonData, forKey: key)
                let syncSuccess = keyValueStore.synchronize()
                if syncSuccess {
                    print("☁️ Saved \(key) to iCloud (\(dataSize) bytes)")
                } else {
                    print("❌ Failed to sync \(key) to iCloud - possibly quota exceeded")
                    // Fall back to local storage
                    UserDefaults.standard.set(jsonData, forKey: fallbackKey)
                    print("💾 Saved \(key) locally as fallback")
                    return
                }
            }
            
            // Always save locally as backup
            UserDefaults.standard.set(jsonData, forKey: fallbackKey)
            print("💾 Saved \(key) locally")
            
        } catch {
            print("❌ Failed to encode \(key): \(error)")
        }
    }
    
    private func loadDataFromiCloud<T: Codable>(key: String, fallbackKey: String, type: T.Type) -> T? {
        var data: Data?
        
        // Try to load from iCloud first
        if iCloudAvailable {
            data = keyValueStore.data(forKey: key)
            if data != nil {
                print("☁️ Loaded \(key) from iCloud")
            }
        }
        
        // Fallback to local storage
        if data == nil {
            data = UserDefaults.standard.data(forKey: fallbackKey)
            if data != nil {
                print("💾 Loaded \(key) from local storage")
            }
        }
        
        guard let data = data else {
            print("📭 No data found for \(key)")
            return nil
        }
        
        do {
            let decoded = try JSONDecoder().decode(type, from: data)
            return decoded
        } catch {
            print("❌ Failed to decode \(key): \(error)")
            return nil
        }
    }
    
    // MARK: - Synchronization
    private func synchronizeFromiCloud() {
        guard iCloudAvailable else { return }
        
        print("🔄 Synchronizing all data from iCloud...")
        
        // Post notifications to trigger UI updates
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
        }
    }
    
    func forceSyncToiCloud() {
        guard iCloudAvailable else {
            print("❌ Cannot sync: iCloud not available")
            return
        }
        
        print("🚀 Force syncing to iCloud...")
        keyValueStore.synchronize()
    }
    
    func clearAllCloudData() {
        guard iCloudAvailable else {
            print("❌ Cannot clear: iCloud not available")
            return
        }
        
        let keys = [weightEntriesKey, workoutEntriesKey, foodEntriesKey, goalsKey, goalCategoriesKey]
        for key in keys {
            keyValueStore.removeObject(forKey: key)
            print("🗑️ Removed iCloud key: \(key)")
        }
        keyValueStore.synchronize()
        print("🗑️ Cleared all iCloud data and synced")
    }
    
    // MARK: - Data Migration
    func migrateLocalDataToiCloud() {
        guard iCloudAvailable else {
            print("❌ Cannot migrate: iCloud not available")
            return
        }
        
        print("📦 Migrating local data to iCloud...")
        
        // Migrate existing UserDefaults data to iCloud
        if let weightData = UserDefaults.standard.data(forKey: "stored_weight_entries") {
            keyValueStore.set(weightData, forKey: weightEntriesKey)
        }
        
        if let workoutData = UserDefaults.standard.data(forKey: "stored_workout_entries") {
            keyValueStore.set(workoutData, forKey: workoutEntriesKey)
        }
        
        if let foodData = UserDefaults.standard.data(forKey: "stored_food_entries") {
            keyValueStore.set(foodData, forKey: foodEntriesKey)
        }
        
        if let goalsData = UserDefaults.standard.data(forKey: "stored_goals") {
            keyValueStore.set(goalsData, forKey: goalsKey)
        }
        
        if let categoriesData = UserDefaults.standard.data(forKey: "goalCategories") {
            keyValueStore.set(categoriesData, forKey: goalCategoriesKey)
        }
        
        keyValueStore.synchronize()
        print("✅ Migration to iCloud completed")
    }
    
    // MARK: - Storage Status
    func getStorageStatus() -> (String, String) {
        if iCloudAvailable {
            let usage = getCurrentStorageUsage()
            return ("☁️ iCloud", "Using \(usage)KB of 1024KB limit")
        } else {
            return ("💾 Local", "Device storage only")
        }
    }
    
    private func getCurrentStorageUsage() -> Int {
        var totalBytes = 0
        
        // Check all our keys
        let keys = [weightEntriesKey, workoutEntriesKey, foodEntriesKey, goalsKey, goalCategoriesKey]
        
        for key in keys {
            if let data = keyValueStore.data(forKey: key) {
                totalBytes += data.count
                print("📊 Key '\(key)': \(data.count) bytes")
            }
        }
        
        print("📊 Total iCloud KV usage: \(totalBytes) bytes (\(totalBytes/1024)KB)")
        return totalBytes / 1024 // Convert to KB
    }
    
    // MARK: - Cleanup
    deinit {
        notificationCenter.removeObserver(self)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
} 