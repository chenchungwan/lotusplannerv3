import Foundation
import CoreData
import CloudKit

// MARK: - Custom Log Item Data Model
struct CustomLogItemData: Identifiable, Codable {
    let id: UUID
    var title: String
    var isEnabled: Bool
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Custom Log Entry Data Model
struct CustomLogEntryData: Identifiable, Codable {
    let id: UUID
    var itemId: UUID
    var date: Date
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        itemId: UUID,
        date: Date,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.itemId = itemId
        self.date = date
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Custom Log Container for iCloud Sync
struct CustomLogContainer: Codable {
    var items: [CustomLogItemData]
    var entries: [CustomLogEntryData]
    var lastSyncDate: Date
    
    init(items: [CustomLogItemData] = [], entries: [CustomLogEntryData] = [], lastSyncDate: Date = Date()) {
        self.items = items
        self.entries = entries
        self.lastSyncDate = lastSyncDate
    }
}

// MARK: - Custom Log Helper Functions
extension CustomLogEntryData {
    /// Get the associated item for this entry
    func getItem(from items: [CustomLogItemData]) -> CustomLogItemData? {
        return items.first { $0.id == itemId }
    }
}

extension CustomLogItemData {
    /// Get completion status for a specific date
    func getCompletionStatus(for date: Date, from entries: [CustomLogEntryData]) -> Bool {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        return entries.contains { entry in
            entry.itemId == self.id && 
            calendar.isDate(entry.date, inSameDayAs: targetDate) && 
            entry.isCompleted
        }
    }
    
    /// Get completion count for a date range
    func getCompletionCount(from startDate: Date, to endDate: Date, from entries: [CustomLogEntryData]) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        return entries.filter { entry in
            entry.itemId == self.id &&
            entry.isCompleted &&
            entry.date >= start &&
            entry.date <= end
        }.count
    }
}
