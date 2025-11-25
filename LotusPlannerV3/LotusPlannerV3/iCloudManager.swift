import Foundation
import SwiftUI
import CloudKit
import CoreData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Debug Helper (disabled for performance)
private func debugPrint(_ message: String) {
    // Debug printing disabled for performance
}

final class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    @Published var iCloudAvailable: Bool = true
    @Published var lastSyncDate: Date?
    @Published private(set) var syncStatus: SyncStatus = .unknown
    
    private let container = CKContainer(identifier: "iCloud.com.chenchungwan.LotusPlannerV3")
    private var persistenceController: PersistenceController {
        PersistenceController.shared
    }
    private let syncStatusDebounceQueue = DispatchQueue(label: "com.chenchungwan.LotusPlannerV3.syncStatus")
    private var pendingStatusWorkItem: DispatchWorkItem?
    private var lastSyncStatus: SyncStatus = .unknown
    
    enum SyncStatus: Equatable {
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
        devLog("🔄 iCloudManager: Initializing...")
        checkiCloudAvailability()
        setupNotifications()
        devLog("✅ iCloudManager: Initialization complete")
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
                        self.updateSyncStatus(.available)
                        #if DEBUG
        #if DEBUG
                        debugPrint("✅ iCloud available and signed in")
        #endif
                        #endif
                    case .noAccount:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.unavailable)
                        #if DEBUG
        #if DEBUG
                        debugPrint("⚠️ No iCloud account signed in")
        #endif
                        #endif
                    case .restricted:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("iCloud access restricted"))
                        #if DEBUG
        #if DEBUG
                        debugPrint("❌ iCloud access restricted")
        #endif
                        #endif
                    case .couldNotDetermine:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("Could not determine iCloud status"))
                        #if DEBUG
        #if DEBUG
                        debugPrint("❓ Could not determine iCloud status")
        #endif
                        #endif
                    case .temporarilyUnavailable:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("iCloud temporarily unavailable"))
                        #if DEBUG
        #if DEBUG
                        debugPrint("⏳ iCloud temporarily unavailable")
        #endif
                        #endif
                    @unknown default:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.unknown)
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
                    self.updateSyncStatus(.error(error.localizedDescription))
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
        
        updateSyncStatus(.syncing)
        
        // NSPersistentCloudKitContainer handles sync automatically
        // We just need to trigger a context save to ensure local changes are pushed
        let context = persistenceController.container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
                updateSyncStatus(.available)
                #if DEBUG
        #if DEBUG
                debugPrint("✅ Local changes synced to iCloud")
        #endif
                #endif
                
                // Post notification for UI updates
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                updateSyncStatus(.error("Sync failed: \(error.localizedDescription)"))
                #if DEBUG
        #if DEBUG
                debugPrint("❌ Failed to sync to iCloud: \(error.localizedDescription)")
        #endif
                #endif
            }
        } else {
            updateSyncStatus(.available)
            #if DEBUG
        #if DEBUG
            debugPrint("ℹ️ No local changes to sync")
        #endif
            #endif
        }
    }
    
    func forceSyncToiCloud() {
        guard iCloudAvailable else {
            updateSyncStatus(.error("iCloud not available"))
            return
        }
        
        updateSyncStatus(.syncing)
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
                updateSyncStatus(.available)
                #if DEBUG
        #if DEBUG
                debugPrint("✅ Force sync completed")
        #endif
                #endif
                
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                updateSyncStatus(.error("Force sync failed: \(error.localizedDescription)"))
                #if DEBUG
        #if DEBUG
                debugPrint("❌ Force sync failed: \(error.localizedDescription)")
        #endif
                #endif
            }
        } else {
            lastSyncDate = Date()
            updateSyncStatus(.available)
            #if DEBUG
        #if DEBUG
            debugPrint("✅ Force sync completed (no changes)")
        #endif
            #endif
        }
    }
    
    func forceCompleteSync() {
        devLog("🔄 iCloudManager: forceCompleteSync() called")
        
        // Immediate UI feedback
        updateSyncStatus(.syncing)
        #if DEBUG
        #if DEBUG
        debugPrint("🔄 Starting complete sync...")
        #endif
        #endif
        
        Task {
            // Check iCloud status first
            devLog("🔄 iCloudManager: Checking iCloud account status...")
            do {
                let status = try await container.accountStatus()
                devLog("🔄 iCloudManager: iCloud status = \(status.rawValue)")
                await MainActor.run {
                    switch status {
                    case .available:
                        self.iCloudAvailable = true
                        devLog("✅ iCloudManager: iCloud account verified")
                    default:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("iCloud account not available"))
                        devLog("❌ iCloudManager: iCloud account not available (status: \(status.rawValue))")
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateSyncStatus(.error("Account check failed: \(error.localizedDescription)"))
                    devLog("❌ iCloudManager: Account check failed: \(error.localizedDescription)")
                }
                return
            }
            
            // Force a complete refresh and sync
            devLog("🔄 iCloudManager: Starting Core Data refresh...")
            await MainActor.run {
                let context = persistenceController.container.viewContext
                
                // STEP 1: Save any pending local changes to trigger export
                if context.hasChanges {
                    do {
                        devLog("💾 iCloudManager: Saving pending changes to trigger export...")
                        devLog("💾   Inserted: \(context.insertedObjects.count), Updated: \(context.updatedObjects.count), Deleted: \(context.deletedObjects.count)")
                        try context.save()
                        devLog("✅ iCloudManager: Local changes saved, export should begin")
                    } catch {
                        updateSyncStatus(.error("Save failed: \(error.localizedDescription)"))
                        devLog("❌ iCloudManager: Failed to save pending changes: \(error.localizedDescription)")
                        
                        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                        let errorFeedback = UINotificationFeedbackGenerator()
                        errorFeedback.notificationOccurred(.error)
                        #endif
                        return
                    }
                }
                
                // STEP 2: Reset context to clear cache
                devLog("🔄 iCloudManager: Resetting context to clear cached data...")
                context.reset()
            }
            
            // STEP 3: Wait for CloudKit export/import (NSPersistentCloudKitContainer syncs asynchronously)
            devLog("⏳ iCloudManager: Waiting 10 seconds for CloudKit export/import...")
            devLog("⏳   (NSPersistentCloudKitContainer needs time to export changes to CloudKit)")
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds (increased from 5)
            
            // STEP 4: Create multiple background contexts to force import polling
            // NSPersistentCloudKitContainer imports when new contexts are created
            devLog("🔄 iCloudManager: Polling CloudKit for changes...")
            
            for i in 1...3 {
                let pollingContext = persistenceController.container.newBackgroundContext()
                pollingContext.automaticallyMergesChangesFromParent = true
                pollingContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                
                do {
                    try await pollingContext.perform {
                        devLog("🔄 iCloudManager: Polling attempt \(i)...")
                        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                        request.fetchLimit = 5
                        let results = try pollingContext.fetch(request)
                        devLog("🔄 iCloudManager: Poll \(i) found \(results.count) TaskTimeWindows")
                    }
                } catch {
                    devLog("⚠️ iCloudManager: Poll \(i) failed: \(error)")
                }
                
                // Small delay between polls
                if i < 3 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
            }
            
            // STEP 5: Final wait for imports to complete
            devLog("⏳ iCloudManager: Waiting 3 more seconds for imports to merge...")
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            await MainActor.run {
                devLog("🔄 iCloudManager: Reloading all managers from Core Data...")
                
                // STEP 6: Create a final fresh context to ensure we get the latest data
                let freshContext = persistenceController.container.newBackgroundContext()
                freshContext.automaticallyMergesChangesFromParent = true
                
                // Perform a final fetch to ensure merge happens
                Task {
                    do {
                        try await freshContext.perform {
                            let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                            let allWindows = try freshContext.fetch(request)
                            devLog("🔄 iCloudManager: Final fetch found \(allWindows.count) TaskTimeWindows in Core Data")
                        }
                        
                        await MainActor.run {
                            // STEP 7: Now reload all managers with the fresh data
                            let beforeCount = TaskTimeWindowManager.shared.timeWindows.count
                            devLog("🔄 iCloudManager: Current count before reload: \(beforeCount)")
                            
                            TaskTimeWindowManager.shared.loadTimeWindows()
                            CustomLogManager.shared.refreshData()
                            LogsViewModel.shared.reloadData()
                            
                            let afterCount = TaskTimeWindowManager.shared.timeWindows.count
                            devLog("🔄 iCloudManager: Count after reload: \(afterCount)")
                            
                            if afterCount != beforeCount {
                                devLog("✅ iCloudManager: Data changed! \(beforeCount) → \(afterCount)")
                } else {
                                devLog("ℹ️ iCloudManager: No data changes detected")
                            }
                            
                    lastSyncDate = Date()
                    updateSyncStatus(.available)
                            devLog("✅ iCloudManager: Complete sync finished")
                    
                    // Provide haptic success feedback
                    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    #endif
                            
                            NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                        }
                    } catch {
                        await MainActor.run {
                        updateSyncStatus(.error("Merge failed: \(error.localizedDescription)"))
                            devLog("❌ iCloudManager: Failed to merge CloudKit changes: \(error)")
                        }
                    }
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
    
    // MARK: - CloudKit Direct Query Diagnostics
    func diagnoseCloudKitData() async {
        devLog("🔍 DIAGNOSTICS: Starting CloudKit data check...")
        
        // Check account status
        do {
            let status = try await container.accountStatus()
            devLog("🔍 DIAGNOSTICS: Account status = \(status.rawValue)")
            guard status == .available else {
                devLog("❌ DIAGNOSTICS: iCloud account not available")
                return
            }
        } catch {
            devLog("❌ DIAGNOSTICS: Failed to check account: \(error)")
            return
        }
        
        // Query CloudKit directly for CD_TaskTimeWindow records
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "CD_TaskTimeWindow", predicate: NSPredicate(value: true))
        
        devLog("🔍 DIAGNOSTICS: Querying CloudKit for CD_TaskTimeWindow records...")
        
        do {
            let (matchResults, _) = try await database.records(matching: query, resultsLimit: 25)
            
            devLog("🔍 DIAGNOSTICS: Found \(matchResults.count) TaskTimeWindow records in CloudKit")
            
            var successfulRecords: [(CKRecord.ID, CKRecord)] = []
            var failedRecords: [(CKRecord.ID, Error)] = []
            
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    successfulRecords.append((recordID, record))
                case .failure(let error):
                    failedRecords.append((recordID, error))
                }
            }
            
            let sortedRecords = successfulRecords.sorted { lhs, rhs in
                let lhsDate = lhs.1.modificationDate ?? .distantPast
                let rhsDate = rhs.1.modificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
            
            for (index, entry) in sortedRecords.prefix(10).enumerated() {
                let recordID = entry.0
                let record = entry.1
                let taskId = record.value(forKey: "CD_taskId") as? String ?? "nil"
                let startTime = record.value(forKey: "CD_startTime") as? Date ?? Date()
                let endTime = record.value(forKey: "CD_endTime") as? Date ?? Date()
                let modDate = record.modificationDate ?? Date()
                
                devLog("🔍   Record \(index + 1):")
                devLog("      recordID: \(recordID.recordName)")
                devLog("      taskId: \(taskId)")
                devLog("      startTime: \(startTime)")
                devLog("      endTime: \(endTime)")
                devLog("      modified: \(modDate)")
            }
            
            for (recordID, error) in failedRecords {
                devLog("❌   Record \(recordID.recordName) failed: \(error)")
            }
            
            // Now check what's in local Core Data
            await MainActor.run {
                let context = persistenceController.container.viewContext
                let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
                request.fetchLimit = 10
                
                do {
                    let localWindows = try context.fetch(request)
                    devLog("🔍 DIAGNOSTICS: Found \(localWindows.count) TaskTimeWindow records in local Core Data")
                    
                    for (index, window) in localWindows.enumerated() {
                        devLog("🔍   Local \(index + 1):")
                        devLog("      taskId: \(window.taskId ?? "nil")")
                        devLog("      startTime: \(window.startTime ?? Date())")
                        devLog("      endTime: \(window.endTime ?? Date())")
                        devLog("      updatedAt: \(window.updatedAt ?? Date())")
                    }
                } catch {
                    devLog("❌ DIAGNOSTICS: Failed to fetch local Core Data: \(error)")
                }
            }
            
            devLog("✅ DIAGNOSTICS: CloudKit check completed")
            
        } catch {
            devLog("❌ DIAGNOSTICS: CloudKit query failed: \(error)")
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
    
    private func updateSyncStatus(_ newStatus: SyncStatus) {
        syncStatusDebounceQueue.async {
            guard self.lastSyncStatus != newStatus else { return }
            
            if self.lastSyncStatus == .syncing && newStatus == .syncing {
                return
            }
            
            self.pendingStatusWorkItem?.cancel()
            
            let applyStatus = {
                DispatchQueue.main.async {
                    guard self.syncStatus != newStatus else { return }
                    self.syncStatus = newStatus
                    self.lastSyncStatus = newStatus
                }
            }
            
            let shouldDelay = self.lastSyncStatus == .syncing && newStatus == .available
            if shouldDelay {
                let workItem = DispatchWorkItem(block: applyStatus)
                self.pendingStatusWorkItem = workItem
                self.syncStatusDebounceQueue.asyncAfter(deadline: .now() + 0.4, execute: workItem)
            } else {
                applyStatus()
            }
        }
    }
    
    // MARK: - Notifications Setup
    private func setupNotifications() {
        devLog("🔔 iCloudManager: Setting up notification observers...")
        
        // Listen for app becoming active to trigger a sync check
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            devLog("📱 iCloudManager: App entering foreground, checking for CloudKit updates...")
            
            // Give CloudKit a moment to sync, then reload
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                devLog("🔄 iCloudManager: Reloading data after foreground...")
                let beforeCount = TaskTimeWindowManager.shared.timeWindows.count
                
                TaskTimeWindowManager.shared.loadTimeWindows()
                CustomLogManager.shared.refreshData()
                LogsViewModel.shared.reloadData()
                
                let afterCount = TaskTimeWindowManager.shared.timeWindows.count
                if afterCount != beforeCount {
                    devLog("✅ iCloudManager: Data changed after foreground! \(beforeCount) → \(afterCount)")
                    self.lastSyncDate = Date()
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                } else {
                    devLog("ℹ️ iCloudManager: No data changes detected")
                }
            }
        }
        
        // Listen for CloudKit import completion from Persistence layer
        NotificationCenter.default.addObserver(
            forName: Notification.Name("cloudKitImportCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            devLog("☁️ iCloudManager: ✅ CloudKit import notification RECEIVED!")
            devLog("☁️ iCloudManager: Notification timestamp: \(notification.userInfo?["timestamp"] ?? "unknown")")
            devLog("☁️ iCloudManager: Current task time windows count: \(TaskTimeWindowManager.shared.timeWindows.count)")
            
            // Reload all managers when CloudKit imports new data
            devLog("☁️ iCloudManager: Reloading TaskTimeWindowManager...")
            TaskTimeWindowManager.shared.loadTimeWindows()
            
            devLog("☁️ iCloudManager: Reloading CustomLogManager...")
            CustomLogManager.shared.refreshData()
            
            devLog("☁️ iCloudManager: Reloading LogsViewModel...")
            LogsViewModel.shared.reloadData()
            
            devLog("☁️ iCloudManager: After reload - task time windows count: \(TaskTimeWindowManager.shared.timeWindows.count)")
            
            self.lastSyncDate = Date()
            self.updateSyncStatus(.available)
            
            devLog("✅ iCloudManager: Data reloaded after CloudKit import")
            
            // Provide haptic feedback
            #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
            #endif
            
            // Post notification for UI updates
            NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
        }
        
        devLog("🔔 iCloudManager: Notification observer setup complete")
        
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            devLog("📡 iCloudManager: CloudKit remote changes received!")
            devLog("📡   Notification: \(notification)")
            
            // Update last sync date
            self.lastSyncDate = Date()
            self.updateSyncStatus(.syncing)
            
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
                        devLog("📡 iCloudManager: Fetching updated data from Core Data...")
                        
                        // Fetch all data types to ensure they're up to date
                        let weightRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
                        let workoutRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
                        let foodRequest: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
                        let taskTimeRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                        let customLogEntryRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
                        let customLogItemRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
                        
                        let weights = try backgroundContext.fetch(weightRequest)
                        let workouts = try backgroundContext.fetch(workoutRequest)
                        let foods = try backgroundContext.fetch(foodRequest)
                        let taskTimes = try backgroundContext.fetch(taskTimeRequest)
                        let customLogEntries = try backgroundContext.fetch(customLogEntryRequest)
                        let customLogItems = try backgroundContext.fetch(customLogItemRequest)
                        
                        devLog("📡   Fetched: \(weights.count) weights, \(workouts.count) workouts, \(foods.count) foods")
                        devLog("📡   Fetched: \(taskTimes.count) task times, \(customLogEntries.count) custom log entries, \(customLogItems.count) custom log items")
                        
                        // Save background context to ensure changes are merged
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                            devLog("📡   Background context saved changes")
                        }
                    }
                    
                    await MainActor.run {
                        self.updateSyncStatus(.available)
                        devLog("✅ iCloudManager: CloudKit changes merged successfully")
                        
                        // Reload TaskTimeWindowManager after remote changes
                        TaskTimeWindowManager.shared.loadTimeWindows()
                        
                        // Reload CustomLogManager
                        CustomLogManager.shared.refreshData()
                        
                        // Post notification for UI updates
                        NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                        
                        // Provide haptic feedback
                        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.success)
                        #endif
                    }
                } catch {
                    await MainActor.run {
                        self.updateSyncStatus(.error(error.localizedDescription))
                        #if DEBUG
                        debugPrint("❌ Failed to merge CloudKit changes: \(error)")
                        #endif
                        
                        // Provide error feedback
                        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.error)
                        #endif
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
} 