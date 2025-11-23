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
    
    private let cloudKitContainer = CKContainer.default()
    private let privateDatabase: CKDatabase
    
    private let itemsKey = "customLogItems"
    private let entriesKey = "customLogEntries"
    private let lastSyncKey = "customLogLastSync"
    
    private init() {
        self.privateDatabase = cloudKitContainer.privateCloudDatabase
        cleanupDuplicateCustomLogData()
        loadData()
        setupCloudKitSubscription()
        Task {
            await fetchFromiCloud()
        }
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
            print("Error loading custom log items: \(error)")
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
            print("Error loading custom log entries: \(error)")
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
        syncToCloudKit()
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
                syncToCloudKit()
            }
        } catch {
            print("Error updating custom log item: \(error)")
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
            print("Error deleting custom log item: \(error)")
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
            print("Error deleting custom log entries: \(error)")
        }
        
        saveContext()
        loadData()
        updateCustomLogVisibility()
        syncToCloudKit()
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
                print("Error updating entry: \(error)")
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
        
        syncToCloudKit()
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
                print("Error saving custom log context: \(error)")
            }
        }
    }
    
    // MARK: - CloudKit Sync
    private func setupCloudKitSubscription() {
        // Setup CloudKit subscription for real-time updates
        // Implementation similar to other managers
    }
    
    func syncToCloudKit() {
        Task {
            await performCloudKitSync()
        }
    }
    
    private func performCloudKitSync() async {
        syncStatus = .syncing
        
        do {
            // Create container for sync
            let container = CustomLogContainer(
                items: items,
                entries: entries,
                lastSyncDate: Date()
            )
            
            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(container)
            
            // Create CloudKit record
            let record = CKRecord(recordType: "CustomLogData")
            record["data"] = data
            record["lastSyncDate"] = Date()
            
            // Save to CloudKit
            _ = try await privateDatabase.save(record)
            
            // Update local sync date
            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            
            syncStatus = .success
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Custom Log CloudKit sync error: \(error)")
        }
    }
    
    func forceSync() async {
        await performCloudKitSync()
    }
    
    private func fetchFromiCloud() async {
        do {
            let query = CKQuery(recordType: "CustomLogData", predicate: NSPredicate(value: true))
            let results = try await privateDatabase.records(matching: query)
            
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let data = record["data"] as? Data {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let container = try decoder.decode(CustomLogContainer.self, from: data)
                        
                        // Update local data if CloudKit data is newer
                        if let cloudSyncDate = record["lastSyncDate"] as? Date,
                           let localSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
                           cloudSyncDate > localSyncDate {
                            
                            await updateCoreDataFromCloudKit(container: container)
                        }
                    }
                case .failure(let error):
                    print("Custom Log CloudKit fetch error: \(error)")
                }
            }
        } catch {
            print("Custom Log CloudKit fetch error: \(error)")
        }
    }
    
    private func saveItemToCoreData(_ item: CustomLogItemData) {
        // Check if item already exists
        let request: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.id.uuidString)
        
        do {
            let existingEntities = try context.fetch(request)
            let entity: CustomLogItem
            
            if let existing = existingEntities.first {
                // Update existing item
                entity = existing
            } else {
                // Create new item
                entity = CustomLogItem(context: context)
                entity.id = item.id.uuidString
                entity.createdAt = item.createdAt
            }
            
            // Set/update properties
            entity.title = item.title
            entity.isEnabled = item.isEnabled
            entity.displayOrder = Int16(item.displayOrder)
            entity.updatedAt = item.updatedAt
            entity.userId = "default" // Add default userId for CloudKit sync
        } catch {
            print("Error saving item to Core Data: \(error)")
        }
    }
    
    private func saveEntryToCoreData(_ entry: CustomLogEntryData) {
        // Check if entry already exists
        let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id.uuidString)
        
        do {
            let existingEntities = try context.fetch(request)
            let entity: CustomLogEntry
            
            if let existing = existingEntities.first {
                // Update existing entry
                entity = existing
            } else {
                // Create new entry
                entity = CustomLogEntry(context: context)
                entity.id = entry.id.uuidString
                entity.createdAt = entry.createdAt
            }
            
            // Set/update properties
            entity.itemId = entry.itemId.uuidString
            entity.date = entry.date
            entity.isCompleted = entry.isCompleted
            entity.updatedAt = entry.updatedAt
            entity.userId = "default" // Add default userId for CloudKit sync
        } catch {
            print("Error saving entry to Core Data: \(error)")
        }
    }
    
    private func updateCoreDataFromCloudKit(container: CustomLogContainer) async {
        // Clear existing data
        let itemRequest: NSFetchRequest<NSFetchRequestResult> = CustomLogItem.fetchRequest()
        let deleteItemRequest = NSBatchDeleteRequest(fetchRequest: itemRequest)
        
        let entryRequest: NSFetchRequest<NSFetchRequestResult> = CustomLogEntry.fetchRequest()
        let deleteEntryRequest = NSBatchDeleteRequest(fetchRequest: entryRequest)
        
        do {
            try context.execute(deleteItemRequest)
            try context.execute(deleteEntryRequest)
            
            // Save new data
            for item in container.items {
                saveItemToCoreData(item)
            }
            
            for entry in container.entries {
                saveEntryToCoreData(entry)
            }
            
            try context.save()
            
            // Update local arrays
            await MainActor.run {
                items = container.items
                entries = container.entries
                updateCustomLogVisibility()
            }
            
        } catch {
            print("Error updating Core Data from CloudKit: \(error)")
        }
    }
    
    func refreshData() {
        cleanupDuplicateCustomLogData()
        loadData()
    }
    
    // MARK: - Delete All Data
    func deleteAllData() {
        // Clear local arrays
        items.removeAll()
        entries.removeAll()
        
        // Delete all from Core Data
        let itemRequest: NSFetchRequest<NSFetchRequestResult> = CustomLogItem.fetchRequest()
        let deleteItemRequest = NSBatchDeleteRequest(fetchRequest: itemRequest)
        
        let entryRequest: NSFetchRequest<NSFetchRequestResult> = CustomLogEntry.fetchRequest()
        let deleteEntryRequest = NSBatchDeleteRequest(fetchRequest: entryRequest)
        
        do {
            try context.execute(deleteItemRequest)
            try context.execute(deleteEntryRequest)
            try context.save()
            
            // Clear UserDefaults
            UserDefaults.standard.removeObject(forKey: lastSyncKey)
            
            // Update visibility
            updateCustomLogVisibility()
            
            // Sync deletion to CloudKit
            syncToCloudKit()
        } catch {
            print("Error deleting all custom log data: \(error)")
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
            var uniqueKeys: [String: CustomLogItem] = [:]
            var duplicates: [CustomLogItem] = []
            
            for item in allItems {
                let normalizedTitle = (item.title ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let key = "\(normalizedTitle)|\(item.displayOrder)"
                
                if let existing = uniqueKeys[key] {
                    let existingUpdated = existing.updatedAt ?? existing.createdAt ?? .distantPast
                    let itemUpdated = item.updatedAt ?? item.createdAt ?? .distantPast
                    
                    if itemUpdated > existingUpdated {
                        duplicates.append(existing)
                        uniqueKeys[key] = item
                    } else {
                        duplicates.append(item)
                    }
                } else {
                    uniqueKeys[key] = item
                }
            }
            
            if !duplicates.isEmpty {
                duplicates.forEach { context.delete($0) }
                saveContext()
                print("🧹 CustomLogManager: Removed \(duplicates.count) duplicate custom log item(s)")
            }
        } catch {
            print("❌ CustomLogManager: Failed to cleanup duplicate items: \(error)")
        }
    }
    
    private func cleanupDuplicateEntries() {
        let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomLogEntry.updatedAt, ascending: false)]
        
        do {
            let allEntries = try context.fetch(request)
            var uniqueKeys: [String: CustomLogEntry] = [:]
            var duplicates: [CustomLogEntry] = []
            
            let calendar = Calendar.current
            
            for entry in allEntries {
                let normalizedDate = entry.date.map { calendar.startOfDay(for: $0) } ?? .distantPast
                let key = "\(entry.itemId ?? "")|\(normalizedDate.timeIntervalSince1970)"
                
                if let existing = uniqueKeys[key] {
                    let existingUpdated = existing.updatedAt ?? existing.createdAt ?? .distantPast
                    let entryUpdated = entry.updatedAt ?? entry.createdAt ?? .distantPast
                    
                    if entryUpdated > existingUpdated {
                        duplicates.append(existing)
                        uniqueKeys[key] = entry
                    } else {
                        duplicates.append(entry)
                    }
                } else {
                    uniqueKeys[key] = entry
                }
            }
            
            if !duplicates.isEmpty {
                duplicates.forEach { context.delete($0) }
                saveContext()
                print("🧹 CustomLogManager: Removed \(duplicates.count) duplicate custom log entry/entries")
            }
        } catch {
            print("❌ CustomLogManager: Failed to cleanup duplicate entries: \(error)")
        }
    }
}
