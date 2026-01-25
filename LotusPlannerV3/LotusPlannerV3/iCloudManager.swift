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

    // Debounce properties for data reloading
    private var lastReloadDate: Date?
    private let reloadDebounceInterval: TimeInterval = 3.0 // Wait at least 3 seconds between reloads
    private let reloadQueue = DispatchQueue(label: "com.chenchungwan.LotusPlannerV3.reloadDebounce")
    private var pendingReloadWorkItem: DispatchWorkItem?
    
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
                        self.updateSyncStatus(.available)
                        devLog("✅ iCloud available and signed in", level: .info, category: .cloud)
                    case .noAccount:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.unavailable)
                        devLog("⚠️ No iCloud account signed in", level: .warning, category: .cloud)
                    case .restricted:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("iCloud access restricted"))
                        devLog("❌ iCloud access restricted", level: .error, category: .cloud)
                    case .couldNotDetermine:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("Could not determine iCloud status"))
                        devLog("❓ Could not determine iCloud status", level: .warning, category: .cloud)
                    case .temporarilyUnavailable:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.error("iCloud temporarily unavailable"))
                        devLog("⏳ iCloud temporarily unavailable", level: .warning, category: .cloud)
                    @unknown default:
                        self.iCloudAvailable = false
                        self.updateSyncStatus(.unknown)
                        devLog("❓ Unknown iCloud status", level: .warning, category: .cloud)
                    }
                }
            } catch {
                await MainActor.run {
                    self.iCloudAvailable = false
                    self.updateSyncStatus(.error(error.localizedDescription))
                    devLog("❌ iCloud status check failed: \(error.localizedDescription)", level: .error, category: .cloud)
                }
            }
        }
    }
    
    // MARK: - CloudKit Sync Methods
    func synchronizeFromiCloud() {
        guard iCloudAvailable else {
            devLog("⚠️ iCloud not available for sync", level: .warning, category: .cloud)
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
                devLog("✅ Local changes synced to iCloud", level: .info, category: .cloud)
                
                // Post notification for UI updates
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                updateSyncStatus(.error("Sync failed: \(error.localizedDescription)"))
                devLog("❌ Failed to sync to iCloud: \(error.localizedDescription)", level: .error, category: .cloud)
            }
        } else {
            updateSyncStatus(.available)
            devLog("ℹ️ No local changes to sync", level: .info, category: .cloud)
        }
    }
    
    func forceSyncToiCloud() {
        guard iCloudAvailable else {
            updateSyncStatus(.error("iCloud not available"))
            return
        }
        
        updateSyncStatus(.syncing)
        devLog("🔄 Force syncing to iCloud...", level: .info, category: .cloud)
        
        // Force CloudKit to sync by triggering a context refresh
        let context = persistenceController.container.viewContext
        context.refreshAllObjects()
        
        // Save any pending changes
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
                updateSyncStatus(.available)
                devLog("✅ Force sync completed", level: .info, category: .cloud)
                
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                updateSyncStatus(.error("Force sync failed: \(error.localizedDescription)"))
                devLog("❌ Force sync failed: \(error.localizedDescription)", level: .error, category: .cloud)
            }
        } else {
            lastSyncDate = Date()
            updateSyncStatus(.available)
            devLog("✅ Force sync completed (no changes)", level: .info, category: .cloud)
        }
    }
    
    func forceCompleteSync() {
        devLog("🔄 iCloudManager: forceCompleteSync() called")
        
        // Immediate UI feedback
        updateSyncStatus(.syncing)
        devLog("🔄 Starting complete sync...", level: .info, category: .cloud)
        
        Task {
            // Check iCloud status first
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    switch status {
                    case .available:
                        self.iCloudAvailable = true
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
            await MainActor.run {
                let context = persistenceController.container.viewContext

                // STEP 1: Save any pending local changes to trigger export
                if context.hasChanges {
                    do {
                        devLog("💾 iCloudManager: Saving \(context.insertedObjects.count) inserted, \(context.updatedObjects.count) updated, \(context.deletedObjects.count) deleted")
                        try context.save()
                    } catch {
                        updateSyncStatus(.error("Save failed: \(error.localizedDescription)"))
                        devLog("❌ iCloudManager: Failed to save pending changes: \(error.localizedDescription)")
                        return
                    }
                }

                // STEP 2: Reset context to clear cache
                context.reset()
            }
            
            // STEP 3: Wait for CloudKit export/import (NSPersistentCloudKitContainer syncs asynchronously)
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

            // STEP 4: Create multiple background contexts to force import polling
            // NSPersistentCloudKitContainer imports when new contexts are created
            for i in 1...3 {
                let pollingContext = persistenceController.container.newBackgroundContext()
                pollingContext.automaticallyMergesChangesFromParent = true
                pollingContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

                do {
                    try await pollingContext.perform {
                        // Fetch multiple entity types to trigger import
                        let taskTimeRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                        taskTimeRequest.fetchLimit = 5
                        let goalRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
                        goalRequest.fetchLimit = 5
                        let goalCategoryRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
                        goalCategoryRequest.fetchLimit = 5

                        _ = try pollingContext.fetch(taskTimeRequest)
                        _ = try pollingContext.fetch(goalRequest)
                        _ = try pollingContext.fetch(goalCategoryRequest)
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
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            await MainActor.run {
                // STEP 6: Create a final fresh context to ensure we get the latest data
                let freshContext = persistenceController.container.newBackgroundContext()
                freshContext.automaticallyMergesChangesFromParent = true

                // Perform a final fetch to ensure merge happens
                Task {
                    do {
                        try await freshContext.perform {
                            // Fetch all entity types to ensure complete merge
                            let taskTimeRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                            let goalRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
                            let goalCategoryRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()

                            _ = try freshContext.fetch(taskTimeRequest)
                            _ = try freshContext.fetch(goalRequest)
                            _ = try freshContext.fetch(goalCategoryRequest)
                        }

                        await MainActor.run {
                            // STEP 7: Now reload all managers with the fresh data
                            let beforeCount = TaskTimeWindowManager.shared.timeWindows.count

                            TaskTimeWindowManager.shared.loadTimeWindows()
                            CustomLogManager.shared.refreshData()
                            LogsViewModel.shared.reloadData()
                            GoalsManager.shared.refreshData()

                            let afterCount = TaskTimeWindowManager.shared.timeWindows.count

                            if afterCount != beforeCount {
                                devLog("✅ iCloudManager: Data changed! \(beforeCount) → \(afterCount)")
                            }

                            lastSyncDate = Date()
                            updateSyncStatus(.available)
                            devLog("✅ iCloudManager: Complete sync finished")

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
        devLog("🔍 Diagnosing iCloud Setup...", level: .info, category: .cloud)
        devLog("Container ID: iCloud.com.chenchungwan.LotusPlannerV3", level: .info, category: .cloud)
        devLog("iCloud Available: \(iCloudAvailable)", level: .info, category: .cloud)
        devLog("Sync Status: \(syncStatus.description)", level: .info, category: .cloud)
        devLog("Last Sync: \(lastSyncDate?.description ?? "Never")", level: .info, category: .cloud)
        
        Task {
            do {
                let accountStatus = try await container.accountStatus()
                devLog("Account Status: \(accountStatus)", level: .info, category: .cloud)
                
                // Check if we can access the database
                let database = container.privateCloudDatabase
                devLog("Private Database: \(database)", level: .info, category: .cloud)
                
                await MainActor.run {
                    devLog("✅ iCloud diagnosis complete", level: .info, category: .cloud)
                }
            } catch {
                await MainActor.run {
                    devLog("❌ iCloud diagnosis failed: \(error.localizedDescription)", level: .error, category: .cloud)
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
            devLog("⚠️ Cannot migrate: iCloud not available", level: .warning, category: .cloud)
            return
        }
        
        devLog("🔄 Migrating local data to iCloud...", level: .info, category: .cloud)
        
        // NSPersistentCloudKitContainer handles migration automatically
        // We just need to ensure all data is saved to trigger CloudKit sync
        let context = persistenceController.container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                lastSyncDate = Date()
                devLog("✅ Local data migration to iCloud completed", level: .info, category: .cloud)
                
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
            } catch {
                devLog("❌ Migration failed: \(error.localizedDescription)", level: .error, category: .cloud)
            }
        } else {
            devLog("ℹ️ No local data to migrate", level: .info, category: .cloud)
        }
    }
    
    func clearAllCloudData() {
        devLog("🗑️ Note: CloudKit data clearing should be done through CloudKit Console", level: .warning, category: .cloud)
        devLog("This method cannot directly clear CloudKit data due to security restrictions", level: .warning, category: .cloud)
        
        // We can only clear local Core Data, which will eventually sync the deletions
        Task {
            await MainActor.run {
                let context = persistenceController.container.viewContext
                
                // This is dangerous - only for development/testing
                #if DEBUG
                CoreDataManager.shared.deleteAllLogs()
                devLog("⚠️ Local data cleared (DEBUG mode only)", level: .warning, category: .cloud)
                #else
                devLog("❌ Data clearing disabled in production for safety", level: .error, category: .cloud)
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
    
    // MARK: - Debounced Data Reloading
    private func debouncedReloadAllData() {
        reloadQueue.async { [weak self] in
            guard let self = self else { return }

            // Check if we reloaded recently
            if let lastReload = self.lastReloadDate,
               Date().timeIntervalSince(lastReload) < self.reloadDebounceInterval {
                // Too soon, skip full reload but still post notification for listeners
                DispatchQueue.main.async {
                    devLog("⏭️ iCloudManager: Skipping debounced reload (too soon), but posting notification")
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                }
                return
            }

            // Cancel any pending reload
            self.pendingReloadWorkItem?.cancel()

            // Schedule new reload
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    let beforeCount = TaskTimeWindowManager.shared.timeWindows.count

                    TaskTimeWindowManager.shared.loadTimeWindows()
                    CustomLogManager.shared.refreshData()
                    LogsViewModel.shared.reloadData()
                    GoalsManager.shared.refreshData()

                    let afterCount = TaskTimeWindowManager.shared.timeWindows.count

                    if beforeCount != afterCount {
                        devLog("✅ iCloudManager: Debounced reload completed (\(beforeCount) → \(afterCount))")
                    }

                    self.lastSyncDate = Date()
                    self.lastReloadDate = Date()
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                }
            }

            self.pendingReloadWorkItem = workItem
            self.reloadQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    // MARK: - Notifications Setup
    private func setupNotifications() {
        // Listen for app becoming active to trigger a sync check
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Give CloudKit a moment to sync, then reload (debounced)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.debouncedReloadAllData()
            }
        }

        // Listen for CloudKit import completion from Persistence layer
        NotificationCenter.default.addObserver(
            forName: Notification.Name("cloudKitImportCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.updateSyncStatus(.available)
            self.debouncedReloadAllData()
        }
        
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

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
                        // Fetch all data types to ensure they're up to date
                        let weightRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
                        let workoutRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
                        let foodRequest: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
                        let waterRequest: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
                        let taskTimeRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
                        let customLogEntryRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
                        let customLogItemRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
                        let goalRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
                        let goalCategoryRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()

                        let weights = try backgroundContext.fetch(weightRequest)
                        let workouts = try backgroundContext.fetch(workoutRequest)
                        let foods = try backgroundContext.fetch(foodRequest)
                        let waters = try backgroundContext.fetch(waterRequest)
                        let taskTimes = try backgroundContext.fetch(taskTimeRequest)
                        let customLogEntries = try backgroundContext.fetch(customLogEntryRequest)
                        let customLogItems = try backgroundContext.fetch(customLogItemRequest)
                        let goals = try backgroundContext.fetch(goalRequest)
                        let goalCategories = try backgroundContext.fetch(goalCategoryRequest)

                        devLog("📡 iCloudManager: Remote changes - \(weights.count) weights, \(workouts.count) workouts, \(foods.count) foods, \(waters.count) waters, \(taskTimes.count) task times, \(customLogEntries.count) custom log entries, \(customLogItems.count) custom log items, \(goals.count) goals, \(goalCategories.count) goal categories")

                        // Save background context to ensure changes are merged
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                        }
                    }

                    await MainActor.run {
                        self.updateSyncStatus(.available)
                        devLog("✅ iCloudManager: CloudKit changes merged successfully")

                        // Use debounced reload to prevent multiple rapid reloads
                        self.debouncedReloadAllData()
                    }
                } catch {
                    await MainActor.run {
                        self.updateSyncStatus(.error(error.localizedDescription))
                        devLog("❌ iCloudManager: Failed to merge CloudKit changes: \(error)")
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
} 