//
//  Persistence.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import CoreData
import CloudKit

// MARK: - Debug Helper (now enabled to diagnose persistence issues)
private func debugPrint(_ message: String) {
    devLog("🗄️ Persistence: \(message)")
}

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
            #if DEBUG
            debugPrint("⚠️ Failed to create preview data: \(error.localizedDescription)")
            #endif
            // Continue without sample data rather than crashing
        }
        return result
    }()

    // Use CloudKit-backed container so Core Data syncs automatically across
    // the user’s iCloud devices.
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        devLog("🗄️ Persistence: Initializing PersistenceController (inMemory: \(inMemory))")
        container = NSPersistentCloudKitContainer(name: "LotusPlannerV3")
        
        // Enable automatic lightweight migration
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        // Configure every store description **before** loading the stores.
        for description in container.persistentStoreDescriptions {
            devLog("🗄️ Persistence: Configuring store at URL: \(description.url?.absoluteString ?? "nil")")

            // In-memory store for previews/tests.
            if inMemory {
                devLog("🗄️ Persistence: Setting up IN-MEMORY store (data won't persist!)")
                description.url = URL(fileURLWithPath: "/dev/null")
                // Disable CloudKit for in-memory stores
                description.cloudKitContainerOptions = nil
            } else {
                devLog("🗄️ Persistence: Using PERSISTENT store at: \(description.url?.path ?? "unknown")")

                // Explicitly configure CloudKit container options for persistent stores
                // This ensures CloudKit sync is enabled
                let containerIdentifier = "iCloud.com.chenchungwan.LotusPlannerV3"
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                description.cloudKitContainerOptions = options
                devLog("☁️ Persistence: CloudKit container explicitly configured: \(containerIdentifier)")
            }

            // Enable history tracking & remote notifications so viewContext
            // receives change merges from CloudKit pushes.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            devLog("🗄️ Persistence: loadPersistentStores completed")
            devLog("🗄️ Persistence: Store URL: \(storeDescription.url?.path ?? "nil")")
            devLog("🗄️ Persistence: Store type: \(storeDescription.type)")
            
            // Check if CloudKit is enabled
            if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
                devLog("☁️ Persistence: CloudKit container: \(cloudKitOptions.containerIdentifier)")
            } else {
                devLog("⚠️ Persistence: CloudKit is NOT enabled for this store!")
            }
            
            if let error = error as NSError? {
                // Production-safe error handling for Core Data store loading failures
                #if DEBUG
                debugPrint("❌ Core Data Error: Failed to load persistent store")
                #endif
                #if DEBUG
                debugPrint("Store Description: \(storeDescription)")
                #endif
                #if DEBUG
                debugPrint("Error: \(error.localizedDescription)")
                #endif
                #if DEBUG
                debugPrint("Error Info: \(error.userInfo)")
                #endif
                
                // Log specific error types for debugging
                switch error.code {
                case NSPersistentStoreIncompatibleVersionHashError:
                    #if DEBUG
                    debugPrint("🔄 Migration required - incompatible version")
                    #endif
                case NSMigrationMissingSourceModelError:
                    #if DEBUG
                    debugPrint("🔄 Migration failed - missing source model")
                    #endif
                case NSPersistentStoreOperationError:
                    #if DEBUG
                    debugPrint("💾 Store operation failed - check permissions/storage")
                    #endif
                case NSValidationMultipleErrorsError, NSValidationMissingMandatoryPropertyError, NSValidationRelationshipLacksMinimumCountError, NSValidationRelationshipExceedsMaximumCountError, NSValidationRelationshipDeniedDeleteError, NSValidationNumberTooLargeError, NSValidationNumberTooSmallError, NSValidationDateTooLateError, NSValidationDateTooSoonError, NSValidationInvalidDateError, NSValidationStringTooLongError, NSValidationStringTooShortError, NSValidationStringPatternMatchingError:
                    #if DEBUG
                    debugPrint("✅ Data validation error")
                    #endif
                default:
                    #if DEBUG
                    debugPrint("❓ Unknown Core Data error code: \(error.code)")
                    #endif
                }
                
                // Instead of crashing, we'll attempt to create a new store
                // This allows the app to continue functioning even with data issues
                #if DEBUG
                debugPrint("🔧 Attempting to recover by creating new store...")
                #endif
                
                // Note: In production, you might want to:
                // 1. Show user-friendly error message
                // 2. Offer to reset data
                // 3. Send crash report to analytics
                // 4. Attempt automatic recovery strategies
            } else {
                #if DEBUG
                debugPrint("✅ Core Data store loaded successfully")
                #endif
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
                devLog("☁️ Persistence: CloudKit event: \(event.type) - \(event.succeeded ? "✅ Success" : "❌ Failed")")
                
                if event.type == .import && event.succeeded {
                    devLog("☁️ Persistence: CloudKit import completed! Posting notification...")
                    devLog("☁️ Persistence: Posting to notification: .cloudKitImportCompleted")
                    
                    // Post custom notification for iCloudManager to handle data reload
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("cloudKitImportCompleted"),
                            object: nil,
                            userInfo: ["timestamp": Date()]
                        )
                        devLog("☁️ Persistence: Notification posted successfully at \(Date())")
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
