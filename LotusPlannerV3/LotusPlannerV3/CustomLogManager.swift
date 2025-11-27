import Foundation
import CoreData
import CloudKit
import SwiftUI

@MainActor
class CustomLogManager: ObservableObject {
    static let shared = CustomLogManager()
    
    @Published var items: [CustomLogItemData] = []
    @Published var entries: [CustomLogEntryData] = []
    @Published var isLoading = false
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
        
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .syncing: return "Syncing..."
            case .success: return "Synced"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    private let persistenceController = PersistenceController.shared
    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    // NOTE: CloudKit sync is handled automatically by NSPersistentCloudKitContainer
    // Manual CloudKit sync code removed to prevent conflicts with automatic sync

    private init() {
        cleanupDuplicateCustomLogData()
        loadData()
    }
    
    // MARK: - Data Loading
    func loadData() {
        loadItems()
        loadEntries()
    }
    
    private func loadItems() {
        let request: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomLogItem.displayOrder, ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            items = entities.compactMap { entity in
                CustomLogItemData(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    title: entity.title ?? "",
                    isEnabled: entity.isEnabled,
                    displayOrder: Int(entity.displayOrder),
                    createdAt: entity.createdAt ?? Date(),
                    updatedAt: entity.updatedAt ?? Date()
                )
            }
        } catch {
            devLog("Error loading custom log items: \(error)")
        }
    }
    
    private func loadEntries() {
        let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomLogEntry.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            entries = entities.compactMap { entity in
                CustomLogEntryData(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    itemId: UUID(uuidString: entity.itemId ?? "") ?? UUID(),
                    date: entity.date ?? Date(),
                    isCompleted: entity.isCompleted,
                    createdAt: entity.createdAt ?? Date(),
                    updatedAt: entity.updatedAt ?? Date()
                )
            }
        } catch {
            devLog("Error loading custom log entries: \(error)")
        }
    }
    
    // MARK: - Item Management
    func addItem(_ item: CustomLogItemData) {
        let entity = CustomLogItem(context: context)
        entity.id = item.id.uuidString
        entity.title = item.title
        entity.isEnabled = item.isEnabled
        entity.displayOrder = Int16(item.displayOrder)
        entity.createdAt = item.createdAt
        entity.updatedAt = item.updatedAt
        
        saveContext()
        loadItems()
        updateCustomLogVisibility()
        // CloudKit sync handled automatically by NSPersistentCloudKitContainer
    }
    
    func updateItem(_ item: CustomLogItemData) {
        let request: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            if let entity = entities.first {
                entity.title = item.title
                entity.isEnabled = item.isEnabled
                entity.displayOrder = Int16(item.displayOrder)
                entity.updatedAt = Date()
                
                saveContext()
                loadItems()
                // CloudKit sync handled automatically by NSPersistentCloudKitContainer
            }
        } catch {
            devLog("Error updating custom log item: \(error)")
        }
    }
    
    func deleteItem(_ itemId: UUID) {
        // Delete the item
        let itemRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "id == %@", itemId.uuidString)
        
        do {
            let entities = try context.fetch(itemRequest)
            for entity in entities {
                context.delete(entity)
            }
        } catch {
            devLog("Error deleting custom log item: \(error)")
        }
        
        // Delete all entries for this item
        let entryRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        entryRequest.predicate = NSPredicate(format: "itemId == %@", itemId.uuidString)
        
        do {
            let entities = try context.fetch(entryRequest)
            for entity in entities {
                context.delete(entity)
            }
        } catch {
            devLog("Error deleting custom log entries: \(error)")
        }
        
        saveContext()
        loadData()
        updateCustomLogVisibility()
        // CloudKit sync handled automatically by NSPersistentCloudKitContainer
    }
    
    func reorderItems(_ newOrder: [UUID]) {
        for (index, itemId) in newOrder.enumerated() {
            if let itemIndex = items.firstIndex(where: { $0.id == itemId }) {
                var updatedItem = items[itemIndex]
                updatedItem.displayOrder = index
                updatedItem.updatedAt = Date()
                updateItem(updatedItem)
            }
        }
    }
    
    // MARK: - Entry Management
    func toggleEntry(for itemId: UUID, date: Date) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Find existing entry
        if let existingIndex = entries.firstIndex(where: { 
            $0.itemId == itemId && calendar.isDate($0.date, inSameDayAs: targetDate) 
        }) {
            // Toggle existing entry in Core Data
            let entry = entries[existingIndex]
            let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", entry.id.uuidString)
            
            do {
                let entities = try context.fetch(request)
                if let entity = entities.first {
                    entity.isCompleted.toggle()
                    entity.updatedAt = Date()
                    saveContext()
                    loadEntries()
                }
            } catch {
                devLog("Error updating entry: \(error)")
            }
        } else {
            // Create new entry
            let entry = CustomLogEntryData(
                itemId: itemId,
                date: targetDate,
                isCompleted: true
            )
            
            let entity = CustomLogEntry(context: context)
            entity.id = entry.id.uuidString
            entity.itemId = entry.itemId.uuidString
            entity.date = entry.date
            entity.isCompleted = entry.isCompleted
            entity.createdAt = entry.createdAt
            entity.updatedAt = entry.updatedAt
            
            saveContext()
            loadEntries()
        }

        // CloudKit sync handled automatically by NSPersistentCloudKitContainer
    }
    
    func getEntriesForDate(_ date: Date) -> [CustomLogEntryData] {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        return entries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: targetDate)
        }
    }
    
    func getCompletionStatus(for itemId: UUID, date: Date) -> Bool {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        return entries.contains { entry in
            entry.itemId == itemId &&
            calendar.isDate(entry.date, inSameDayAs: targetDate) &&
            entry.isCompleted
        }
    }
    
    // MARK: - Core Data
    private func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                devLog("Error saving custom log context: \(error)")
            }
        }
    }
    
    // MARK: - CloudKit Sync
    // NOTE: All CloudKit sync is now handled automatically by NSPersistentCloudKitContainer
    // Manual CloudKit sync functions removed to prevent conflicts
    
    func refreshData() {
        cleanupDuplicateCustomLogData()
        loadData()
    }
    
    // MARK: - Delete All Data
    func deleteAllData() {
        // Clear local arrays
        items.removeAll()
        entries.removeAll()

        // Delete all from Core Data using individual deletes (NOT batch delete)
        // This ensures CloudKit sync gets triggered properly
        let itemRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        let entryRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()

        do {
            // Fetch all entities
            let allItems = try context.fetch(itemRequest)
            let allEntries = try context.fetch(entryRequest)

            // Delete them individually so CloudKit sync is triggered
            for item in allItems {
                context.delete(item)
            }

            for entry in allEntries {
                context.delete(entry)
            }

            // Save to trigger CloudKit export of deletions
            try context.save()

            devLog("✅ CustomLogManager: Deleted \(allItems.count) items and \(allEntries.count) entries from Core Data")
            devLog("☁️ CustomLogManager: CloudKit will automatically sync deletions via NSPersistentCloudKitContainer")

            // Update visibility
            updateCustomLogVisibility()

        } catch {
            devLog("❌ CustomLogManager: Error deleting all custom log data: \(error)")
        }
    }
    
    // MARK: - Visibility Management
    private func updateCustomLogVisibility() {
        let hasItems = !items.isEmpty
        let appPrefs = AppPreferences.shared
        
        // Enable custom logs if there are items, disable if no items
        if appPrefs.showCustomLogs != hasItems {
            appPrefs.updateShowCustomLogs(hasItems)
        }
    }

    // MARK: - Duplicate Cleanup
    func cleanupDuplicateCustomLogData() {
        cleanupDuplicateItems()
        cleanupDuplicateEntries()
    }
    
    private func cleanupDuplicateItems() {
        let request: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomLogItem.updatedAt, ascending: false)]

        do {
            let allItems = try context.fetch(request)
            var uniqueIds: [String: CustomLogItem] = [:]
            var duplicates: [CustomLogItem] = []

            for item in allItems {
                // Use UUID id as the unique key (not title)
                guard let itemId = item.id else {
                    devLog("⚠️ CustomLogManager: Found item with nil id, deleting...")
                    duplicates.append(item)
                    continue
                }

                if let existing = uniqueIds[itemId] {
                    // Found duplicate UUID - keep the more recently updated one
                    let existingUpdated = existing.updatedAt ?? existing.createdAt ?? .distantPast
                    let itemUpdated = item.updatedAt ?? item.createdAt ?? .distantPast

                    if itemUpdated > existingUpdated {
                        duplicates.append(existing)
                        uniqueIds[itemId] = item
                    } else {
                        duplicates.append(item)
                    }
                } else {
                    uniqueIds[itemId] = item
                }
            }

            if !duplicates.isEmpty {
                duplicates.forEach { context.delete($0) }
                saveContext()
                devLog("🧹 CustomLogManager: Removed \(duplicates.count) duplicate custom log item(s) with same UUID")
            }
        } catch {
            devLog("❌ CustomLogManager: Failed to cleanup duplicate items: \(error)")
        }
    }
    
    private func cleanupDuplicateEntries() {
        let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomLogEntry.updatedAt, ascending: false)]

        do {
            let allEntries = try context.fetch(request)
            var uniqueIds: [String: CustomLogEntry] = [:]
            var duplicates: [CustomLogEntry] = []

            for entry in allEntries {
                // Use UUID id as the unique key (not itemId+date)
                guard let entryId = entry.id else {
                    devLog("⚠️ CustomLogManager: Found entry with nil id, deleting...")
                    duplicates.append(entry)
                    continue
                }

                if let existing = uniqueIds[entryId] {
                    // Found duplicate UUID - keep the more recently updated one
                    let existingUpdated = existing.updatedAt ?? existing.createdAt ?? .distantPast
                    let entryUpdated = entry.updatedAt ?? entry.createdAt ?? .distantPast

                    if entryUpdated > existingUpdated {
                        duplicates.append(existing)
                        uniqueIds[entryId] = entry
                    } else {
                        duplicates.append(entry)
                    }
                } else {
                    uniqueIds[entryId] = entry
                }
            }

            if !duplicates.isEmpty {
                duplicates.forEach { context.delete($0) }
                saveContext()
                devLog("🧹 CustomLogManager: Removed \(duplicates.count) duplicate custom log entry/entries with same UUID")
            }
        } catch {
            devLog("❌ CustomLogManager: Failed to cleanup duplicate entries: \(error)")
        }
    }
}
