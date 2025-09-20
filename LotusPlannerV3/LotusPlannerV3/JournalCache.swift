import Foundation
import PencilKit

class JournalCache {
    static let shared = JournalCache()
    
    private var cache = NSCache<NSString, NSData>()
    private let queue = DispatchQueue(label: "com.app.journalCache")
    
    private init() {
        // Set cache limits
        cache.countLimit = 30 // Keep up to 30 drawings in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    func cacheDrawing(_ drawing: PKDrawing, for date: Date) {
        queue.async {
            let data = drawing.dataRepresentation() as NSData
            self.cache.setObject(data, forKey: self.keyForDate(date))
            print("📝 Cached drawing for date: \(date)")
        }
    }
    
    func getCachedDrawing(for date: Date) -> PKDrawing? {
        queue.sync {
            guard let data = cache.object(forKey: keyForDate(date)) as Data? else { return nil }
            do {
                let drawing = try PKDrawing(data: data)
                print("📝 Retrieved drawing from cache for date: \(date)")
                return drawing
            } catch {
                print("📝 Error creating drawing from cached data: \(error)")
                // Remove invalid cache entry
                removeCachedDrawing(for: date)
                return nil
            }
        }
    }
    
    func clearCache() {
        queue.async {
            self.cache.removeAllObjects()
            print("📝 Cleared drawing cache")
        }
    }
    
    func removeCachedDrawing(for date: Date) {
        queue.async {
            self.cache.removeObject(forKey: self.keyForDate(date))
            print("📝 Removed cached drawing for date: \(date)")
        }
    }
    
    private func keyForDate(_ date: Date) -> NSString {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) as NSString
    }
}
