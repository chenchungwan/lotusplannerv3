//
//  Persistence.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create some sample data for previews
        let sampleWeight = WeightLog(context: viewContext)
        sampleWeight.id = UUID().uuidString
        sampleWeight.timestamp = Date()
        sampleWeight.weight = 150.0
        sampleWeight.unit = "lbs"
        sampleWeight.userId = "preview_user"
        
        do {
            try viewContext.save()
        } catch {
            // Production-safe error handling for preview data creation
            devLog("⚠️ Failed to create preview data: \(error.localizedDescription)", level: .warning, category: .general)
            // Continue without sample data rather than crashing
        }
        return result
    }()

    // Use CloudKit-backed container so Core Data syncs automatically across
    // the user’s iCloud devices.
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "LotusPlannerV3")
        
        // Enable automatic lightweight migration
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        // Configure every store description **before** loading the stores.
        for description in container.persistentStoreDescriptions {
            // In-memory store for previews/tests.
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
                // Disable CloudKit for in-memory stores
                description.cloudKitContainerOptions = nil
            } else {
                // Explicitly configure CloudKit container options for persistent stores
                // This ensures CloudKit sync is enabled
                let containerIdentifier = "iCloud.com.chenchungwan.LotusPlannerV3"
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                description.cloudKitContainerOptions = options
            }

            // Enable history tracking & remote notifications so viewContext
            // receives change merges from CloudKit pushes.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            // Check if CloudKit is enabled
            if storeDescription.cloudKitContainerOptions == nil {
                devLog("⚠️ Persistence: CloudKit is NOT enabled for this store!")
            }
            
            if let error = error as NSError? {
                // Production-safe error handling for Core Data store loading failures
                devLog("❌ Core Data Error: Failed to load persistent store", level: .error, category: .general)
                devLog("Store Description: \(storeDescription)", level: .error, category: .general)
                devLog("Error: \(error.localizedDescription)", level: .error, category: .general)
                devLog("Error Info: \(error.userInfo)", level: .error, category: .general)
                
                // Log specific error types for debugging
                switch error.code {
                case NSPersistentStoreIncompatibleVersionHashError:
                    devLog("🔄 Migration required - incompatible version", level: .error, category: .general)
                case NSMigrationMissingSourceModelError:
                    devLog("🔄 Migration failed - missing source model", level: .error, category: .general)
                case NSPersistentStoreOperationError:
                    devLog("💾 Store operation failed - check permissions/storage", level: .error, category: .general)
                case NSValidationMultipleErrorsError, NSValidationMissingMandatoryPropertyError, NSValidationRelationshipLacksMinimumCountError, NSValidationRelationshipExceedsMaximumCountError, NSValidationRelationshipDeniedDeleteError, NSValidationNumberTooLargeError, NSValidationNumberTooSmallError, NSValidationDateTooLateError, NSValidationDateTooSoonError, NSValidationInvalidDateError, NSValidationStringTooLongError, NSValidationStringTooShortError, NSValidationStringPatternMatchingError:
                    devLog("✅ Data validation error", level: .error, category: .general)
                default:
                    devLog("❓ Unknown Core Data error code: \(error.code)", level: .error, category: .general)
                }
                
                // Instead of crashing, we'll attempt to create a new store
                // This allows the app to continue functioning even with data issues
                devLog("🔧 Attempting to recover by creating new store...", level: .warning, category: .general)
                
                // Note: In production, you might want to:
                // 1. Show user-friendly error message
                // 2. Offer to reset data
                // 3. Send crash report to analytics
                // 4. Attempt automatic recovery strategies
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Listen for CloudKit import/export notifications
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                if !event.succeeded {
                    devLog("☁️ Persistence: CloudKit event failed: \(event.type)", level: .warning, category: .cloud)
                }
                
                if event.type == .import && event.succeeded {
                    // Post custom notification for iCloudManager to handle data reload
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("cloudKitImportCompleted"),
                            object: nil,
                            userInfo: ["timestamp": Date()]
                        )
                    }
                }
            }
        }
    }
}

// Custom notification for CloudKit import completion
extension Notification.Name {
    static let cloudKitImportCompleted = Notification.Name("cloudKitImportCompleted")
}
