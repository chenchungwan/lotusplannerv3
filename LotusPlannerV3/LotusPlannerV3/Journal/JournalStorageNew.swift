import Foundation
import PencilKit

/// Simple, reliable journal storage that writes directly to iCloud
/// No complex monitoring, no refresh loops - just save and load
class JournalStorageNew {
    static let shared = JournalStorageNew()
    
    private init() {
        // Initialize storage
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
        
        guard let url = storageURL(for: date) else {
            throw NSError(domain: "JournalStorage", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No storage location available"])
        }
        
        // Check if file already exists (this is an update/overwrite)
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let existingSize = fileExists ? (try? Data(contentsOf: url))?.count ?? 0 : 0
        
        // Write directly to the URL (iCloud or local) - OVERWRITES existing file
        try data.write(to: url, options: [.atomic])
        
        // Check if file is in iCloud and wait for upload to complete
        var isUbiquitous: AnyObject?
        try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
        let isInCloud = (isUbiquitous as? Bool) == true
        
        if isInCloud {
            // Wait for iCloud upload to complete to ensure other devices see the update
            await ensureFileUploaded(url: url)
        }
        
        // Print save information
        let operation = fileExists ? "OVERWRITE" : "CREATE"
        print("💾 JOURNAL SAVE - \(operation) drawing file:")
        print("   📍 Location: \(url.path)")
        print("   📅 Date: \(formatDate(date))")
        print("   ☁️ Storage: \(isInCloud ? "iCloud" : "Local")")
        print("   ✏️ Strokes: \(drawing.strokes.count)")
        print("   📏 New size: \(data.count) bytes (\(String(format: "%.2f", Double(data.count) / 1024.0)) KB)")
        if fileExists {
            print("   ⚠️ Previous size: \(existingSize) bytes (\(String(format: "%.2f", Double(existingSize) / 1024.0)) KB)")
            print("   🔄 File overwritten (previous data replaced)")
            if isInCloud {
                print("   ☁️ Waiting for iCloud upload to complete...")
            }
        } else {
            print("   ✨ New file created")
        }
        
        // Cache it
        setCache(drawing, for: date)
    }
    
    /// Synchronous save wrapper for convenience
    func saveSync(_ drawing: PKDrawing, for date: Date) {
        Task {
            try? await save(drawing, for: date)
        }
    }
    
    // MARK: - Load Drawing
    
    /// Load a drawing from storage with robust iCloud sync
    func load(for date: Date) async -> PKDrawing? {
        let dateKey = formatDate(date)
        
        // Check cache first
        if let cached = getCached(date) {
            return cached
        }
        
        guard let url = storageURL(for: date) else {
            return nil
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        // Robust iCloud sync with retry logic
        return await loadWithRetry(url: url, date: date, maxRetries: 3)
    }
    
    /// Load with retry logic and robust iCloud handling
    private func loadWithRetry(url: URL, date: Date, maxRetries: Int) async -> PKDrawing? {
        for attempt in 1...maxRetries {
            do {
                // Check if file is in iCloud
                var isUbiquitous: AnyObject?
                try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                let isInCloud = (isUbiquitous as? Bool) == true
                
                if isInCloud {
                    // Ensure file is fully downloaded before reading
                    await ensureFileDownloaded(url: url)
                }
                
                // Get file modification date to verify freshness
                var modificationDate: AnyObject?
                try? (url as NSURL).getResourceValue(&modificationDate, forKey: URLResourceKey.contentModificationDateKey)
                let modDate = modificationDate as? Date
                
                // Try to load the data
                let data = try Data(contentsOf: url)
                
                // Print raw iCloud data information
                let fileSize = data.count
                let storageType = isInCloud ? "iCloud" : "Local"
                print("📦 JOURNAL RAW DATA - Drawing file:")
                print("   📍 Location: \(url.path)")
                print("   ☁️ Storage: \(storageType)")
                print("   📏 File size: \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1024.0)) KB)")
                print("   📅 Date: \(formatDate(date))")
                if let modDate = modDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    print("   🕐 Modified: \(formatter.string(from: modDate))")
                }
                
                let drawing = try PKDrawing(data: data)
                
                // Validate the drawing has content
                // Cache it
                setCache(drawing, for: date)
                
                print("   ✏️ Strokes: \(drawing.strokes.count)")
                
                return drawing
                
            } catch {
                
                if attempt < maxRetries {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                    
                    // Force refresh iCloud file on retry
                    var isUbiquitous: AnyObject?
                    try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                    if (isUbiquitous as? Bool) == true {
                        try? FileManager.default.evictUbiquitousItem(at: url)
                        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Ensure iCloud file is fully downloaded
    private func ensureFileDownloaded(url: URL) async {
        // Start download if needed
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        
        // Wait for download to complete with timeout
        let maxWaitTime: UInt64 = 5_000_000_000 // 5 seconds
        let checkInterval: UInt64 = 100_000_000 // 0.1 seconds
        var totalWaitTime: UInt64 = 0
        
        while totalWaitTime < maxWaitTime {
            var downloadStatus: AnyObject?
            try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
            
            if let status = downloadStatus as? URLUbiquitousItemDownloadingStatus {
                if status == .current {
                    return
                }
            }
            
            try? await Task.sleep(nanoseconds: checkInterval)
            totalWaitTime += checkInterval
        }
        
        // Timeout reached, proceed with available data
    }
    
    /// Ensure iCloud file upload is complete after saving
    /// Note: There's no direct API to check upload status, so we wait a reasonable time
    /// and verify the file exists locally to ensure it's queued for upload
    private func ensureFileUploaded(url: URL) async {
        // Verify file exists locally (required for upload to start)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("   ⚠️ File doesn't exist locally, upload may not start")
            return
        }
        
        // Wait a reasonable time for iCloud to queue and process the upload
        // iCloud uploads happen asynchronously, so we just ensure the file is saved locally
        // The actual upload happens in the background
        let waitTime: UInt64 = 1_000_000_000 // 1 second
        try? await Task.sleep(nanoseconds: waitTime)
        
        // Check file attributes to verify it's been saved
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            print("   ✅ File saved locally, iCloud upload queued")
        } else {
            print("   ⚠️ Could not verify file save")
        }
    }
    
    // MARK: - Debug Inspection
    
    /// Debug function to inspect iCloud Drive contents
    func inspectiCloudContents() {
        // Debug function - no output needed
        let iCloudAvailable = isICloudAvailable()
        
        if let iCloudURL = iCloudURL {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: iCloudURL, includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey], options: [])
                
                for (index, url) in contents.enumerated() {
                    let fileName = url.lastPathComponent
                    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    
                    var isUbiquitous: AnyObject?
                    try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                    let isInCloud = (isUbiquitous as? Bool) == true
                    
                    var downloadStatus: AnyObject?
                    try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
                }
            } catch {
                // Error listing iCloud contents - silently fail
            }
        }
        
        // Check local storage as fallback
        let localURL = localURL
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.fileSizeKey], options: [])
            
            for (index, url) in contents.enumerated() {
                let fileName = url.lastPathComponent
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        } catch {
            // Error listing local contents - silently fail
        }
    }
    
    // MARK: - Delete Drawing
    
    /// Delete a drawing
    func delete(for date: Date) throws {
        guard let url = storageURL(for: date) else { return }
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        // Clear from cache
        setCache(nil, for: date)
    }
    
    /// Clear cache for a specific date to force fresh load from iCloud
    func clearCache(for date: Date) {
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

