import Foundation
import PencilKit

struct JournalStorage {
    private let baseURL: URL
    
    init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    // Organize by year/month for better performance
    func urlForDate(_ date: Date) -> URL {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        
        // Create directories if needed
        let yearDir = baseURL.appendingPathComponent("\(year)")
        let monthDir = yearDir.appendingPathComponent("\(month)")
        try? FileManager.default.createDirectory(at: monthDir, withIntermediateDirectories: true)
        
        return monthDir.appendingPathComponent(formatDate(date) + ".drawing")
    }
    
    // Keep backup copies
    func createBackup(for date: Date) {
        let sourceURL = urlForDate(date)
        let backupURL = sourceURL.deletingPathExtension().appendingPathExtension("backup.drawing")
        try? FileManager.default.copyItem(at: sourceURL, to: backupURL)
    }
    
    // Helper to format date consistently
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // Get all drawings in a month
    func getDrawingsForMonth(year: Int, month: Int) -> [URL] {
        let monthDir = baseURL
            .appendingPathComponent("\(year)")
            .appendingPathComponent("\(month)")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: monthDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        
        return contents.filter { $0.pathExtension == "drawing" }
    }
}
