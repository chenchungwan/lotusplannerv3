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
        let sampleCategory = GoalCategoryEntity(context: viewContext)
        sampleCategory.id = UUID().uuidString
        sampleCategory.name = "Health & Fitness"
        
        let sampleGoal = GoalEntity(context: viewContext)
        sampleGoal.id = UUID().uuidString
        sampleGoal.desc = "Exercise 3 times per week"
        sampleGoal.isCompleted = false
        sampleGoal.userId = "preview_user"
        sampleGoal.createdAt = Date()
        sampleGoal.categoryId = sampleCategory.id
        
        let sampleWeight = WeightLog(context: viewContext)
        sampleWeight.id = UUID().uuidString
        sampleWeight.timestamp = Date()
        sampleWeight.weight = 150.0
        sampleWeight.unit = "lbs"
        sampleWeight.userId = "preview_user"
        
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    // Use CloudKit-backed container so Core Data syncs automatically across
    // the user’s iCloud devices.
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "LotusPlannerV3")

        // Configure every store description **before** loading the stores.
        for description in container.persistentStoreDescriptions {
            // In-memory store for previews/tests.
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }

            // Enable history tracking & remote notifications so viewContext
            // receives change merges from CloudKit pushes.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // `NSPersistentCloudKitContainer` already creates appropriate
            // cloudKitContainerOptions when the capability is enabled in
            // the project settings, so no extra configuration is required
            // here.
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                print("❌ Core Data error: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                print("✅ Core Data loaded successfully")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
