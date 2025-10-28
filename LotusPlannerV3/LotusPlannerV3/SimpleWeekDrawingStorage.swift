import Foundation
import PencilKit
import CloudKit

class SimpleWeekDrawingStorage: ObservableObject {
    static let shared = SimpleWeekDrawingStorage()
    
    private let container = CKContainer.default()
    private let database: CKDatabase
    
    private init() {
        self.database = container.privateCloudDatabase
    }
    
    // MARK: - Week Key Generation
    
    private func weekKey(for date: Date) -> String {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return "week_\(Int(date.timeIntervalSince1970))"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startDateString = formatter.string(from: weekInterval.start)
        let endDateString = formatter.string(from: weekInterval.end)
        
        return "simple_week_drawing_\(startDateString)_to_\(endDateString)"
    }
    
    // MARK: - Save Drawing
    
    func saveDrawing(_ drawing: PKDrawing, for date: Date) async {
        let weekKey = weekKey(for: date)
        
        do {
            // Convert PKDrawing to Data
            let drawingData = try drawing.dataRepresentation()
            
            // Create CKRecord
            let record = CKRecord(recordType: "SimpleWeekDrawing", recordID: CKRecord.ID(recordName: weekKey))
            record["weekKey"] = weekKey
            record["drawingData"] = drawingData
            record["lastModified"] = Date()
            
            // Save to iCloud
            let _ = try await database.save(record)
            print("🎨 SimpleWeekDrawingStorage: Saved drawing for week \(weekKey)")
            
        } catch {
            print("🎨 SimpleWeekDrawingStorage: Failed to save drawing: \(error)")
        }
    }
    
    // MARK: - Load Drawing
    
    func loadDrawing(for date: Date) async -> PKDrawing? {
        let weekKey = weekKey(for: date)
        
        do {
            // Fetch from iCloud
            let recordID = CKRecord.ID(recordName: weekKey)
            let record = try await database.record(for: recordID)
            
            // Extract drawing data
            guard let drawingData = record["drawingData"] as? Data else {
                print("🎨 SimpleWeekDrawingStorage: No drawing data found for week \(weekKey)")
                return nil
            }
            
            // Convert Data back to PKDrawing
            let drawing = try PKDrawing(data: drawingData)
            print("🎨 SimpleWeekDrawingStorage: Loaded drawing for week \(weekKey)")
            return drawing
            
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("🎨 SimpleWeekDrawingStorage: No drawing found for week \(weekKey)")
            } else {
                print("🎨 SimpleWeekDrawingStorage: Failed to load drawing: \(error)")
            }
            return nil
        }
    }
    
    // MARK: - Delete Drawing
    
    func deleteDrawing(for date: Date) async {
        let weekKey = weekKey(for: date)
        
        do {
            let recordID = CKRecord.ID(recordName: weekKey)
            let _ = try await database.deleteRecord(withID: recordID)
            print("🎨 SimpleWeekDrawingStorage: Deleted drawing for week \(weekKey)")
            
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("🎨 SimpleWeekDrawingStorage: No drawing to delete for week \(weekKey)")
            } else {
                print("🎨 SimpleWeekDrawingStorage: Failed to delete drawing: \(error)")
            }
        }
    }
    
    // MARK: - Check if Drawing Exists
    
    func hasDrawing(for date: Date) async -> Bool {
        let weekKey = weekKey(for: date)
        
        do {
            let recordID = CKRecord.ID(recordName: weekKey)
            let _ = try await database.record(for: recordID)
            return true
        } catch {
            return false
        }
    }
}
