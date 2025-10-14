import Foundation
import PencilKit

/// Simple, reliable journal storage that writes directly to iCloud
/// No complex monitoring, no refresh loops - just save and load
class JournalStorageNew {
    static let shared = JournalStorageNew()
    
    private init() {
        print("📝 JournalStorageNew initialized")
    }
    
    // MARK: - Storage Locations
    
    /// iCloud container URL (if available)
    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("journal_drawings")
    }
    
    /// Local fallback URL (always available)
    private var localURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("journal_drawings")
    }
    
    /// Get the URL where we should save/load drawings
    /// Returns iCloud if available, otherwise local
    private func storageURL(for date: Date) -> URL? {
        let filename = formatDate(date) + ".drawing"
        
        // Try iCloud first
        if let iCloud = iCloudURL {
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
            return iCloud.appendingPathComponent(filename)
        }
        
        // Fallback to local
        let local = localURL
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return local.appendingPathComponent(filename)
    }
    
    /// Format date as filename
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Simple Cache (in-memory only, no disk cache)
    
    private var cache: [String: PKDrawing] = [:]
    private let cacheLock = NSLock()
    
    private func getCached(_ date: Date) -> PKDrawing? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[formatDate(date)]
    }
    
    private func setCache(_ drawing: PKDrawing?, for date: Date) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = formatDate(date)
        if let drawing = drawing {
            cache[key] = drawing
        } else {
            cache.removeValue(forKey: key)
        }
    }
    
    // MARK: - Save Drawing
    
    /// Save a drawing - writes directly to iCloud if available
    func save(_ drawing: PKDrawing, for date: Date) async throws {
        let data = drawing.dataRepresentation()
        let dateStr = formatDate(date)
        
        print("📝 Saving drawing for \(dateStr), size: \(data.count) bytes")
        
        guard let url = storageURL(for: date) else {
            throw NSError(domain: "JournalStorage", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No storage location available"])
        }
        
        // Write directly to the URL (iCloud or local)
        try data.write(to: url, options: [.atomic])
        
        // Cache it
        setCache(drawing, for: date)
        
        // Check if it's in iCloud
        if url.path.contains("Mobile Documents") {
            print("✅ Saved to iCloud: \(url.lastPathComponent)")
        } else {
            print("✅ Saved locally: \(url.lastPathComponent)")
        }
    }
    
    /// Synchronous save wrapper for convenience
    func saveSync(_ drawing: PKDrawing, for date: Date) {
        Task {
            try? await save(drawing, for: date)
        }
    }
    
    // MARK: - Load Drawing
    
    /// Load a drawing from storage
    func load(for date: Date) -> PKDrawing? {
        let dateStr = formatDate(date)
        
        // Check cache first
        if let cached = getCached(date) {
            print("📝 Loaded from cache: \(dateStr)")
            return cached
        }
        
        guard let url = storageURL(for: date) else {
            print("⚠️ No storage location available")
            return nil
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("📝 No drawing file for: \(dateStr)")
            return nil
        }
        
        // Try to load
        do {
            let data = try Data(contentsOf: url)
            let drawing = try PKDrawing(data: data)
            
            // Cache it
            setCache(drawing, for: date)
            
            print("✅ Loaded drawing: \(dateStr) (\(drawing.strokes.count) strokes)")
            return drawing
        } catch {
            print("❌ Failed to load drawing: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Delete Drawing
    
    /// Delete a drawing
    func delete(for date: Date) throws {
        guard let url = storageURL(for: date) else { return }
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            print("🗑️ Deleted drawing: \(formatDate(date))")
        }
        
        // Clear from cache
        setCache(nil, for: date)
    }
    
    // MARK: - Utilities
    
    /// Check if iCloud is available
    func isICloudAvailable() -> Bool {
        return iCloudURL != nil
    }
    
    /// Get storage info for debugging
    func getStorageInfo() -> String {
        let iCloudAvailable = isICloudAvailable()
        let storageType = iCloudAvailable ? "iCloud" : "Local"
        let cacheCount = cache.count
        
        return """
        Storage Type: \(storageType)
        Cached Drawings: \(cacheCount)
        iCloud URL: \(iCloudURL?.path ?? "unavailable")
        Local URL: \(localURL.path)
        """
    }
}

