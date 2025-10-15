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
        loadData()
        setupCloudKitSubscription()
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
            // Toggle existing entry
            var entry = entries[existingIndex]
            entry.isCompleted.toggle()
            entry.updatedAt = Date()
            
            let entity = CustomLogEntry(context: context)
            entity.id = entry.id.uuidString
            entity.itemId = entry.itemId.uuidString
            entity.date = entry.date
            entity.isCompleted = entry.isCompleted
            entity.createdAt = entry.createdAt
            entity.updatedAt = entry.updatedAt
            
            // Delete old entry
            let request: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", entry.id.uuidString)
            
            do {
                let entities = try context.fetch(request)
                for entity in entities {
                    context.delete(entity)
                }
            } catch {
                print("Error deleting old entry: \(error)")
            }
            
            saveContext()
            loadEntries()
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
        // Implementation for CloudKit sync
        // Similar to other managers' sync logic
    }
    
    func forceSync() async {
        await performCloudKitSync()
    }
    
    func refreshData() {
        loadData()
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
}
