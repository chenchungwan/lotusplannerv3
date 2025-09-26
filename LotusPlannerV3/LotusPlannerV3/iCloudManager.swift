import Foundation
import SwiftUI
import CloudKit
import CoreData

// MARK: - Debug Helper
private func debugPrint(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

final class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    @Published var iCloudAvailable: Bool = true
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .unknown
    
    private let container = CKContainer(identifier: "iCloud.com.chenchungwan.LotusPlannerV3")
    private var persistenceController: PersistenceController {
        PersistenceController.shared
    }
    
    enum SyncStatus {
        case unknown
        case available
        case unavailable
        case syncing
        case error(String)
        
        var description: String {
            switch self {
            case .unknown: return "Checking iCloud status..."
            case .available: return "iCloud sync enabled"
            case .unavailable: return "iCloud unavailable"
            case .syncing: return "Syncing with iCloud..."
            case .error(let message): return "Sync error: \(message)"
            }
        }
    }
    
    private init() {
        #if DEBUG
        debugPrint("🔄 Initializing iCloudManager...")
        #endif
        checkiCloudAvailability()
        setupNotifications()
    }
    
    // MARK: - iCloud Availability Check
    private func checkiCloudAvailability() {
        Task {
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    switch status {
                    case .available:
                        self.iCloudAvailable = true
                        self.syncStatus = .available
                        #if DEBUG
        #if DEBUG
                        debugPrint("✅ iCloud available and signed in")
        #endif
                        #endif
                    case .noAccount:
                        self.iCloudAvailable = false
                        self.syncStatus = .unavailable
                        #if DEBUG
        #if DEBUG
                        debugPrint("⚠️ No iCloud account signed in")
        #endif
                        #endif
                    case .restricted:
                        self.iCloudAvailable = false
                        self.syncStatus = .error("iCloud access restricted")
                        #if DEBUG
        #if DEBUG
                        debugPrint("❌ iCloud access restricted")
        #endif
                        #endif
                    case .couldNotDetermine:
                        self.iCloudAvailable = false
                        self.syncStatus = .error("Could not determine iCloud status")
                        #if DEBUG
        #if DEBUG
                        debugPrint("❓ Could not determine iCloud status")
        #endif
                        #endif
                    case .temporarilyUnavailable:
                        self.iCloudAvailable = false
                        self.syncStatus = .error("iCloud temporarily unavailable")
                        #if DEBUG
        #if DEBUG
                        debugPrint("⏳ iCloud temporarily unavailable")
        #endif
                        #endif
                    @unknown default:
                        self.iCloudAvailable = false
                        self.syncStatus = .unknown
                        #if DEBUG
        #if DEBUG
                        debugPrint("❓ Unknown iCloud status")
        #endif
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    self.iCloudAvailable = false
                    self.syncStatus = .error(error.localizedDescription)
                    #if DEBUG
        #if DEBUG
                    debugPrint("❌ iCloud status check failed: \(error.localizedDescription)")
        #endif
                    #endif
                }
            }
        }
    }
    
    // MARK: - CloudKit Sync Methods
    func synchronizeFromiCloud() {
        guard iCloudAvailable else {
            #if DEBUG
        #if DEBUG
            debugPrint("⚠️ iCloud not available for sync")
        #endif
            #endif
            return
        }
        
        syncStatus = .syncing
        
        // NSPersistentCloudKitContainer handles sync automatically
        // We just need to trigger a context save to ensure local changes are pushed
        let context = persistenceController.container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
                syncStatus = .available
                #if DEBUG
        #if DEBUG
                debugPrint("✅ Local changes synced to iCloud")
        #endif
                #endif
                
                // Post notification for UI updates
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                syncStatus = .error("Sync failed: \(error.localizedDescription)")
                #if DEBUG
        #if DEBUG
                debugPrint("❌ Failed to sync to iCloud: \(error.localizedDescription)")
        #endif
                #endif
            }
        } else {
            syncStatus = .available
            #if DEBUG
        #if DEBUG
            debugPrint("ℹ️ No local changes to sync")
        #endif
            #endif
        }
    }
    
    func forceSyncToiCloud() {
        guard iCloudAvailable else {
            syncStatus = .error("iCloud not available")
            return
        }
        
        syncStatus = .syncing
        #if DEBUG
        #if DEBUG
        debugPrint("🔄 Force syncing to iCloud...")
        #endif
        #endif
        
        // Force CloudKit to sync by triggering a context refresh
        let context = persistenceController.container.viewContext
        context.refreshAllObjects()
        
        // Save any pending changes
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
                syncStatus = .available
                #if DEBUG
        #if DEBUG
                debugPrint("✅ Force sync completed")
        #endif
                #endif
                
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                syncStatus = .error("Force sync failed: \(error.localizedDescription)")
                #if DEBUG
        #if DEBUG
                debugPrint("❌ Force sync failed: \(error.localizedDescription)")
        #endif
                #endif
            }
        } else {
            lastSyncDate = Date()
            syncStatus = .available
            #if DEBUG
        #if DEBUG
            debugPrint("✅ Force sync completed (no changes)")
        #endif
            #endif
        }
    }
    
    func forceCompleteSync() {
        // Immediate UI feedback
        syncStatus = .syncing
        #if DEBUG
        #if DEBUG
        debugPrint("🔄 Starting complete sync...")
        #endif
        #endif
        
        Task {
            // Check iCloud status first
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    switch status {
                    case .available:
                        self.iCloudAvailable = true
                        #if DEBUG
        #if DEBUG
                        debugPrint("✅ iCloud account verified")
        #endif
                        #endif
                    default:
                        self.iCloudAvailable = false
                        self.syncStatus = .error("iCloud account not available")
                        #if DEBUG
        #if DEBUG
                        debugPrint("❌ iCloud account not available")
        #endif
                        #endif
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    self.syncStatus = .error("Account check failed: \(error.localizedDescription)")
                    #if DEBUG
        #if DEBUG
                    debugPrint("❌ Account check failed: \(error.localizedDescription)")
        #endif
                    #endif
                }
                return
            }
            
            // Force a complete refresh and sync
            await MainActor.run {
                let context = persistenceController.container.viewContext
                
                #if DEBUG
        #if DEBUG
                debugPrint("🔄 Refreshing Core Data objects...")
        #endif
                #endif
                // Refresh all objects to get latest from CloudKit
                context.refreshAllObjects()
                
                // Save any local changes
                if context.hasChanges {
                    do {
                        #if DEBUG
        #if DEBUG
                        debugPrint("💾 Saving local changes to CloudKit...")
        #endif
                        #endif
                        try context.save()
                        lastSyncDate = Date()
                        syncStatus = .available
                        #if DEBUG
        #if DEBUG
                        debugPrint("✅ Complete sync finished with changes")
        #endif
                        #endif
                        
                        // Provide haptic success feedback
                        let successFeedback = UINotificationFeedbackGenerator()
                        successFeedback.notificationOccurred(.success)
                        
                        NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                    } catch {
                        syncStatus = .error("Sync failed: \(error.localizedDescription)")
                        #if DEBUG
        #if DEBUG
                        debugPrint("❌ Complete sync failed: \(error.localizedDescription)")
        #endif
                        #endif
                        
                        // Provide haptic error feedback
                        let errorFeedback = UINotificationFeedbackGenerator()
                        errorFeedback.notificationOccurred(.error)
                    }
                } else {
                    lastSyncDate = Date()
                    syncStatus = .available
                    #if DEBUG
        #if DEBUG
                    debugPrint("✅ Complete sync finished (no local changes)")
        #endif
                    #endif
                    
                    // Provide haptic success feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                }
            }
        }
    }
    
    func diagnoseICloudSetup() {
        #if DEBUG
        debugPrint("🔍 Diagnosing iCloud Setup...")
        #endif
        #if DEBUG
        debugPrint("Container ID: iCloud.com.chenchungwan.LotusPlannerV3")
        #endif
        #if DEBUG
        debugPrint("iCloud Available: \(iCloudAvailable)")
        #endif
        #if DEBUG
        debugPrint("Sync Status: \(syncStatus.description)")
        #endif
        #if DEBUG
        debugPrint("Last Sync: \(lastSyncDate?.description ?? "Never")")
        #endif
        
        Task {
            do {
                let accountStatus = try await container.accountStatus()
        #if DEBUG
                debugPrint("Account Status: \(accountStatus)")
        #endif
                
                // Check if we can access the database
                let database = container.privateCloudDatabase
        #if DEBUG
                debugPrint("Private Database: \(database)")
        #endif
                
                await MainActor.run {
        #if DEBUG
                    debugPrint("✅ iCloud diagnosis complete")
        #endif
                }
            } catch {
                await MainActor.run {
        #if DEBUG
                    debugPrint("❌ iCloud diagnosis failed: \(error.localizedDescription)")
        #endif
                }
            }
        }
    }
    
    func migrateLocalDataToiCloud() {
        guard iCloudAvailable else {
        #if DEBUG
            debugPrint("⚠️ Cannot migrate: iCloud not available")
        #endif
            return
        }
        
        #if DEBUG
        debugPrint("🔄 Migrating local data to iCloud...")
        #endif
        
        // NSPersistentCloudKitContainer handles migration automatically
        // We just need to ensure all data is saved to trigger CloudKit sync
        let context = persistenceController.container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
        #if DEBUG
                debugPrint("✅ Local data migration to iCloud completed")
        #endif
                
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
        #if DEBUG
                debugPrint("❌ Migration failed: \(error.localizedDescription)")
        #endif
            }
        } else {
        #if DEBUG
            debugPrint("ℹ️ No local data to migrate")
        #endif
        }
    }
    
    func clearAllCloudData() {
        #if DEBUG
        debugPrint("🗑️ Note: CloudKit data clearing should be done through CloudKit Console")
        #endif
        #if DEBUG
        debugPrint("This method cannot directly clear CloudKit data due to security restrictions")
        #endif
        
        // We can only clear local Core Data, which will eventually sync the deletions
        Task {
            await MainActor.run {
                let context = persistenceController.container.viewContext
                
                // This is dangerous - only for development/testing
                #if DEBUG
                CoreDataManager.shared.deleteAllLogs()
        #if DEBUG
                debugPrint("⚠️ Local data cleared (DEBUG mode only)")
        #endif
                #else
        #if DEBUG
                debugPrint("❌ Data clearing disabled in production for safety")
        #endif
                #endif
            }
        }
    }
    
    func getStorageStatus() -> String { 
        return "iCloud via CloudKit (\(syncStatus.description))"
    }
    
    func getCurrentStorageUsage() -> String { 
        return "Managed by CloudKit - Last sync: \(lastSyncDate?.formatted() ?? "Never")"
    }
    
    // MARK: - Journal iCloud Drive Sync
    /// Force sync journal data to iCloud Drive
    func syncJournalToiCloud() async {
        #if DEBUG
        debugPrint("🔄 Starting journal sync to iCloud Drive...")
        #endif
        
        await JournalManager.shared.forceSyncAllJournalData()
        
        #if DEBUG
        debugPrint("✅ Journal sync to iCloud Drive completed")
        #endif
    }
    
    /// Get journal iCloud Drive status
    func getJournaliCloudStatus() -> (isAvailable: Bool, message: String) {
        return JournalManager.shared.getICloudDriveStatus()
    }
    
    // MARK: - Notifications Setup
    private func setupNotifications() {
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            #if DEBUG
            debugPrint("📡 CloudKit remote changes received")
            #endif
            
            // Update last sync date
            self.lastSyncDate = Date()
            self.syncStatus = .syncing
            
            // Force refresh all Core Data objects
            let context = self.persistenceController.container.viewContext
            context.refreshAllObjects()
            
            // Create a background context for fetching fresh data
            let backgroundContext = self.persistenceController.container.newBackgroundContext()
            backgroundContext.automaticallyMergesChangesFromParent = true
            backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            Task {
                do {
                    // Perform fetch in background
                    try await backgroundContext.perform {
                        // Fetch all log types to ensure they're up to date
                        let weightRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
                        let workoutRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
                        let foodRequest: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
                        
                        let _ = try backgroundContext.fetch(weightRequest)
                        let _ = try backgroundContext.fetch(workoutRequest)
                        let _ = try backgroundContext.fetch(foodRequest)
                        
                        // Save background context to ensure changes are merged
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                        }
                    }
                    
                    await MainActor.run {
                        self.syncStatus = .available
                        #if DEBUG
                        debugPrint("✅ CloudKit changes merged successfully")
                        #endif
                        
                        // Post notification for UI updates
                        NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                        
                        // Provide haptic feedback
                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.success)
                    }
                } catch {
                    await MainActor.run {
                        self.syncStatus = .error(error.localizedDescription)
                        #if DEBUG
                        debugPrint("❌ Failed to merge CloudKit changes: \(error)")
                        #endif
                        
                        // Provide error feedback
                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.error)
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
} 