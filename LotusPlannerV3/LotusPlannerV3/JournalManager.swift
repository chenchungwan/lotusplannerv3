import Foundation
import UniformTypeIdentifiers
import PencilKit
import UIKit
// import CloudKit (removed for iCloud Drive-only sync)

/// Layout type for journal views
enum JournalLayoutType {
    case compact
    case expanded
}

/// Handles storage & retrieval of the journal background PDF inside the app sandbox.
class JournalManager: NSObject, NSFilePresenter {
    private let operationLock = NSLock()
    private var activeOperations: [URL: Task<Void, Error>] = [:]
    private let operationQueue = DispatchQueue(label: "com.app.journalManager.operations", qos: .userInitiated)
    
    private func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try block()
    }
    
    private func synchronized<T>(_ block: () async throws -> T) async rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try await block()
    }
    static let shared = JournalManager()
    private override init() {
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    
    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }
    
    private static var metadataQuery: NSMetadataQuery?
    
    // MARK: - NSFilePresenter
    var presentedItemURL: URL? {
        return ubiquityDocsURL?.appendingPathComponent("journal_drawings")
    }
    
    var presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    func presentedItemDidChange() {
        // Handle changes to the drawings directory
        Task { @MainActor in
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
        }
    }
    
    func presentedItemDidGain(_ version: NSFileVersion) {
        // A new version is available (e.g., from another device)
        Task { @MainActor in
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
        }
    }
    
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        // Handle deletion of the drawings directory
        completionHandler(nil)
    }
    
    func presentedItemDidMove(to newURL: URL) {
        // Handle moving of the drawings directory
        Task { @MainActor in
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
        }
    }
    
    // MARK: - Storage roots
    /// iCloud Drive Documents directory for the app (if available)
    private var ubiquityDocsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }
    
    /// Returns the iCloud Documents URL if available
    func getICloudDocsURL() -> URL? {
        return ubiquityDocsURL
    }
    /// Local Documents directory (always available)
    private var localDocsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    /// Preferred Documents directory: iCloud if available, else local
    private func fileName(for layoutType: JournalLayoutType) -> String {
        return "journal_background.pdf"
    }

    private var docsURL: URL {
        // Always prefer iCloud URL for drawings
        if let iCloudURL = ubiquityDocsURL {
            // Ensure iCloud is actually available
            var isUbiquitous: AnyObject?
            try? (iCloudURL as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            if (isUbiquitous as? Bool) == true {
                return iCloudURL
            }
        }
        return localDocsURL
    }

    /// Expose the current storage root for other components (e.g. photos)
    func storageRootURL() -> URL { docsURL }
    
    /// Get the iCloud URL for a drawing if available, otherwise return nil
    private func iCloudDrawingURL(for date: Date) -> URL? {
        guard let iCloudRoot = ubiquityDocsURL else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current // Use local timezone for display
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + ".drawing"
        return iCloudRoot.appendingPathComponent("journal_drawings").appendingPathComponent(name)
    }

    // MARK: - Journal Photos paths (shared)
    private var photosDirectoryURL: URL {
        let dir = docsURL.appendingPathComponent("journal_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func metadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_photos.json"
        return photosDirectoryURL.appendingPathComponent(name)
    }

    /// Attempt to migrate any local-only content into iCloud when it becomes
    /// available so drawings/photos sync across devices. Safe to call repeatedly.
    func migrateLocalToICloudIfNeeded() {
        guard let iCloudRoot = ubiquityDocsURL else { return }
        let fm = FileManager.default
        // Ensure iCloud root and subdirectories exist
        try? fm.createDirectory(at: iCloudRoot, withIntermediateDirectories: true)

        // Helper to move/copy one item
        func moveItem(localURL: URL, iCloudURL: URL) {
            guard fm.fileExists(atPath: localURL.path) else { return }
            if fm.fileExists(atPath: iCloudURL.path) { return }
            // Ensure parent exists
            try? fm.createDirectory(at: iCloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Prefer setUbiquitous to enroll file into iCloud
            do {
                try fm.setUbiquitous(true, itemAt: localURL, destinationURL: iCloudURL)
            } catch {
                // Fallback to copy if setUbiquitous fails
                try? fm.copyItem(at: localURL, to: iCloudURL)
            }
        }

        // Background PDFs (both layouts)
        let compactLocal = localDocsURL.appendingPathComponent(fileName(for: .compact))
        let compactICloud = iCloudRoot.appendingPathComponent(fileName(for: .compact))
        moveItem(localURL: compactLocal, iCloudURL: compactICloud)
        let expandedLocal = localDocsURL.appendingPathComponent(fileName(for: .expanded))
        let expandedICloud = iCloudRoot.appendingPathComponent(fileName(for: .expanded))
        moveItem(localURL: expandedLocal, iCloudURL: expandedICloud)

        // Drawings directory: move each .drawing file
        let localDrawingsDir = localDocsURL.appendingPathComponent("journal_drawings", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: localDrawingsDir, includingPropertiesForKeys: nil) {
            for file in items where file.pathExtension == "drawing" {
                let dest = iCloudRoot.appendingPathComponent("journal_drawings").appendingPathComponent(file.lastPathComponent)
                moveItem(localURL: file, iCloudURL: dest)
            }
        }

        // Photos directory: move each PNG and metadata JSON
        let localPhotosDir = localDocsURL.appendingPathComponent("journal_photos", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: localPhotosDir, includingPropertiesForKeys: nil) {
            for file in items where ["png", "json"].contains(file.pathExtension.lowercased()) {
                let dest = iCloudRoot.appendingPathComponent("journal_photos").appendingPathComponent(file.lastPathComponent)
                moveItem(localURL: file, iCloudURL: dest)
            }
        }
    }
    private func storedURL(for layoutType: JournalLayoutType) -> URL { 
        docsURL.appendingPathComponent(fileName(for: layoutType)) 
    }
    
    /// Save/copy a PDF from a temporary location into Documents, overwriting any previous file.
    func savePDF(from sourceURL: URL, layoutType: JournalLayoutType = .compact) throws {
        let targetURL = storedURL(for: layoutType)
        // Remove old
        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        // Persist path
        UserDefaults.standard.set(targetURL.path, forKey: "journalBackgroundPDFPath_\(layoutType)")
    }

    /// Save raw PDF data (if we can't copy directly due to sandbox restrictions)
    func savePDF(data: Data, layoutType: JournalLayoutType = .compact) throws {
        let targetURL = storedURL(for: layoutType)
        try? FileManager.default.removeItem(at: targetURL)
        try data.write(to: targetURL, options: .atomic)
        UserDefaults.standard.set(targetURL.path, forKey: "journalBackgroundPDFPath_\(layoutType)")
    }
    
    /// URL for the background PDF. Resolution order:
    /// 1. User-selected file in Documents/iCloud directory
    /// 2. Path stored in UserDefaults (legacy)
    /// 3. Bundled resource shipped with the app
    func backgroundPDFURL(for layoutType: JournalLayoutType = .compact) -> URL? {
        let targetURL = storedURL(for: layoutType)
        
        // 1. Previously imported file
        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // 2. Legacy path persisted in UserDefaults
        if let path = UserDefaults.standard.string(forKey: "journalBackgroundPDFPath_\(layoutType)") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return url
            }
        }

        // 3. Fallback to bundled default PDF
        return Bundle.main.url(forResource: "journal_background", withExtension: "pdf")
    }
    
    /// Load PDF data if available.
    func loadPDFData(for layoutType: JournalLayoutType = .compact) -> Data? {
        guard let url = backgroundPDFURL(for: layoutType) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Remove any stored background PDF and legacy paths so the journal uses a blank background.
    func clearBackgroundPDF(layoutType: JournalLayoutType = .compact) {
        let targetURL = storedURL(for: layoutType)
        try? FileManager.default.removeItem(at: targetURL)
        UserDefaults.standard.removeObject(forKey: "journalBackgroundPDFPath_\(layoutType)")
    }

    // MARK: - Drawing Storage
    private var drawingsDirectory: URL {
        let dir = docsURL.appendingPathComponent("journal_drawings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private func drawingURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current // Use local timezone for display
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + ".drawing"
        return drawingsDirectory.appendingPathComponent(name)
    }

    private lazy var storage = JournalStorage(baseURL: docsURL)
    private lazy var versionManager = JournalVersionManager(baseURL: docsURL)
    
    private func performFileOperation(for url: URL, operation: @escaping () async throws -> Void) async throws {
        return try await synchronized {
            // Cancel any existing operation for this URL
            activeOperations[url]?.cancel()
            
            // Create new operation
            let task = Task {
                try await operation()
            }
            activeOperations[url] = task
            
            defer {
                activeOperations.removeValue(forKey: url)
            }
            
            return try await task.value
        }
    }
    
    func saveDrawingAsync(for date: Date, drawing: PKDrawing) async throws {
        // Create a unique temporary file for this save operation
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("drawing.temp")
        
        // Save drawing to temp file first
        let data = drawing.dataRepresentation()
        try data.write(to: tempURL, options: [.atomic])
        
        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Try to save directly to iCloud first
        if let iCloudURL = iCloudDrawingURL(for: date) {
            try await performFileOperation(for: iCloudURL) {
            // Ensure iCloud directory exists
            let iCloudDir = iCloudURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
            
            // Save to iCloud with coordination
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                
                coordinator.coordinate(writingItemAt: iCloudURL, options: [.forReplacing, .forDeleting], error: &coordError) { url in
                    do {
                        let fm = FileManager.default
                        
                        // Remove existing file if it exists
                        if fm.fileExists(atPath: url.path) {
                            try fm.removeItem(at: url)
                        }
                        
                        // First try to write the data directly
                        let data = try Data(contentsOf: tempURL)
                        try data.write(to: url, options: [.atomic])
                        
                        // Verify the file exists in iCloud
                        var isUbiquitous: AnyObject?
                        try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                        let isInICloud = (isUbiquitous as? Bool) == true
                        
                        if !isInICloud {
                            // If not in iCloud, try to explicitly move it there
                            let tempMove = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("drawing")
                            
                            try data.write(to: tempMove, options: [.atomic])
                            try fm.setUbiquitous(true, itemAt: tempMove, destinationURL: url)
                            
                            // Verify again
                            try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                            let isNowInICloud = (isUbiquitous as? Bool) == true
                            
                            if !isNowInICloud {
                                continuation.resume(throwing: NSError(domain: "JournalManager", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "File not found in iCloud after save"]))
                                return
                            }
                        }
                        
                        // Start download to ensure it's available
                        try fm.startDownloadingUbiquitousItem(at: url)
                        
                        print("📝 Successfully saved drawing to iCloud: \(url.lastPathComponent)")
                        continuation.resume()
                    } catch {
                        print("📝 Error saving drawing to iCloud: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
                
                if let error = coordError {
                    continuation.resume(throwing: error)
                }
            }
            
            // Cache the drawing locally
            JournalCache.shared.cacheDrawing(drawing, for: date)
            
            // Post notifications
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
            NotificationCenter.default.post(name: .journalDrawingChanged, object: nil, userInfo: ["url": iCloudURL])
            }
        } else {
            // Fallback to local storage if iCloud is not available
            let localURL = drawingURL(for: date)
            try? FileManager.default.createDirectory(at: drawingsDirectory, withIntermediateDirectories: true)
            
            // Save locally
            let fm = FileManager.default
            if fm.fileExists(atPath: localURL.path) {
                try fm.removeItem(at: localURL)
            }
            try fm.copyItem(at: tempURL, to: localURL)
            
            // Cache the drawing
            JournalCache.shared.cacheDrawing(drawing, for: date)
            
            // Add to sync coordinator for later sync
            JournalSyncCoordinator.shared.addPendingChange(localURL)
            
            // Post notification for UI update
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
        }
    }
    
    func saveDrawing(for date: Date, drawing: PKDrawing) {
        Task {
            try? await saveDrawingAsync(for: date, drawing: drawing)
        }
    }
    
    private func saveDrawingWithRetry(date: Date, drawing: PKDrawing, retryCount: Int = 0) async {
        let maxRetries = 3
        let retryDelay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000 // exponential backoff in seconds
        
        do {
            let data = drawing.dataRepresentation()
            
            // Try to save directly to iCloud first
            if let iCloudURL = iCloudDrawingURL(for: date) {
                do {
                    // Ensure iCloud directory exists
                    let iCloudDir = iCloudURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
                    
                    // Save to iCloud with coordination
                    try writeData(data, to: iCloudURL)
                    print("📝 Saving drawing directly to iCloud: \(iCloudURL.path)")
                    
                    // Verify the file exists in iCloud
                    var isUbiquitous: AnyObject?
                    try? (iCloudURL as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                    let isInICloud = (isUbiquitous as? Bool) == true
                    
                    if !isInICloud {
                        throw NSError(domain: "JournalManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "File not found in iCloud after save"])
                    }
                    
                    // Start download to ensure it's available
                    try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
                    
                    // Cache the drawing locally
                    JournalCache.shared.cacheDrawing(drawing, for: date)
                    
                    // Post notification for UI update
                    NotificationCenter.default.post(name: .journalContentChanged, object: nil)
                    NotificationCenter.default.post(name: .journalDrawingChanged, object: nil, userInfo: ["url": iCloudURL])
                    
                    print("📝 Successfully saved drawing to iCloud for date: \(date)")
                    return
                    
                } catch {
                    print("📝 Error saving to iCloud (attempt \(retryCount + 1)): \(error)")
                    
                    if retryCount < maxRetries {
                        // Wait before retrying
                        try? await Task.sleep(nanoseconds: retryDelay)
                        await saveDrawingWithRetry(date: date, drawing: drawing, retryCount: retryCount + 1)
                        return
                    }
                    
                    // If all retries failed, fall back to local storage
                    throw error
                }
            }
            
            // Fallback to local storage if iCloud is not available or all retries failed
            let localURL = drawingURL(for: date)
            try? FileManager.default.createDirectory(at: drawingsDirectory, withIntermediateDirectories: true)
            
            // Save locally
            try writeData(data, to: localURL)
            print("📝 Saving drawing locally (will sync later): \(localURL.path)")
            
            // Cache the drawing
            JournalCache.shared.cacheDrawing(drawing, for: date)
            
            // Add to sync coordinator for later sync
            JournalSyncCoordinator.shared.addPendingChange(localURL)
            
            // Post notification for UI update
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
            
            print("📝 Successfully saved drawing locally for date: \(date)")
            
        } catch {
            print("📝 Error saving drawing: \(error)")
            // Trigger immediate sync attempt in case of error
            JournalSyncCoordinator.shared.forceSync()
        }
    }
    
    func loadDrawing(for date: Date) -> PKDrawing? {
        // Check cache first
        if let cachedDrawing = JournalCache.shared.getCachedDrawing(for: date) {
            print("📝 Found drawing in cache for date: \(date)")
            return cachedDrawing
        }
        
        do {
            // Try loading from iCloud first
            if let iCloudURL = iCloudDrawingURL(for: date) {
                print("📝 Attempting to load drawing from iCloud: \(iCloudURL.path)")
                
                // Ensure the file is downloaded
                try? FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
                
                if let drawing = try? loadDrawingFromURL(iCloudURL) {
                    print("📝 Successfully loaded drawing from iCloud")
                    JournalCache.shared.cacheDrawing(drawing, for: date)
                    return drawing
                }
            }
            
            // If not in iCloud, try local storage
            let localURL = drawingURL(for: date)
            print("📝 Attempting to load drawing from local storage: \(localURL.path)")
            
            if let drawing = try? loadDrawingFromURL(localURL) {
                print("📝 Successfully loaded drawing from local storage")
                JournalCache.shared.cacheDrawing(drawing, for: date)
                
                // If found locally but not in iCloud, queue for sync
                if let iCloudURL = iCloudDrawingURL(for: date),
                   !FileManager.default.fileExists(atPath: iCloudURL.path) {
                    JournalSyncCoordinator.shared.addPendingChange(localURL)
                }
                
                return drawing
            }
            
            print("📝 No drawing found for date: \(date)")
            return nil
        } catch {
            print("📝 Error loading drawing: \(error)")
            return nil
        }
    }
    
    private func loadDrawingFromURL(_ url: URL) throws -> PKDrawing? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PKDrawing(data: data)
    }

    // MARK: - iCloud Monitoring / Download
    /// Start monitoring the iCloud Documents scope for journal files and trigger downloads.
    func startICloudMonitoring() {
        guard ubiquityDocsURL != nil else { return }
        if JournalManager.metadataQuery != nil { return }
        
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "(kMDItemFSName LIKE[c] '*.drawing') OR (kMDItemFSName LIKE[c] '*_photos.json') OR (kMDItemFSName LIKE[c] '*.png')")
        
        // Add notification observers
        let center = NotificationCenter.default
        center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            self?.handleQueryResults(query, isInitialGathering: true)
            query.enableUpdates()
        }
        
        center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            self?.handleQueryResults(query, isInitialGathering: false)
        }
        
        // Monitor iCloud availability changes
        center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.handleICloudAvailabilityChange()
        }
        
        JournalManager.metadataQuery = query
        query.start()
    }

    func stopICloudMonitoring() {
        guard let query = JournalManager.metadataQuery else { return }
        query.stop()
        
        let center = NotificationCenter.default
        center.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        center.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        center.removeObserver(self, name: .NSUbiquityIdentityDidChange, object: nil)
        
        JournalManager.metadataQuery = nil
    }

    private func handleQueryResults(_ query: NSMetadataQuery, isInitialGathering: Bool) {
        let fm = FileManager.default
        var changedDrawings = false
        
        for item in query.results {
            guard let result = item as? NSMetadataItem,
                  let url = result.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            
            // Check if item is ubiquitous and needs downloading
            var isUbiq: AnyObject?
            var isDownloaded: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiq, forKey: URLResourceKey.isUbiquitousItemKey)
            try? (url as NSURL).getResourceValue(&isDownloaded, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
            
            if (isUbiq as? Bool) == true {
                if url.pathExtension == "drawing" {
                    changedDrawings = true
                }
                
                // Download if not already downloaded
                if isDownloaded as? URLUbiquitousItemDownloadingStatus != .current {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                }
            }
        }
        
        // Post notifications
        if changedDrawings {
            NotificationCenter.default.post(name: .journalDrawingChanged, object: nil)
        }
        NotificationCenter.default.post(name: .journalContentChanged, object: nil)
    }
    
    private func handleICloudAvailabilityChange() {
        // Restart monitoring if iCloud becomes available
        if ubiquityDocsURL != nil {
            stopICloudMonitoring()
            startICloudMonitoring()
            
            // Try to migrate any local files
            migrateLocalToICloudIfNeeded()
        } else {
            stopICloudMonitoring()
        }
        
        // Notify UI to refresh
        NotificationCenter.default.post(name: .journalContentChanged, object: nil)
    }

    /// Hint iCloud to download files for a specific date (drawing and photos metadata) if needed.
    func ensureICloudReady(for date: Date) {
        guard ubiquityDocsURL != nil else { return }
        let fm = FileManager.default
        let drawURL = drawingURL(for: date)
        try? fm.startDownloadingUbiquitousItem(at: drawURL)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let metadata = storageRootURL().appendingPathComponent("journal_photos").appendingPathComponent(formatter.string(from: date) + "_photos.json")
        try? fm.startDownloadingUbiquitousItem(at: metadata)
    }

    // MARK: - Coordinated writes for iCloud reliability
    /// Write data to URL using NSFileCoordinator when iCloud is available to ensure sync picks up changes.
    func writeData(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        
        if ubiquityDocsURL != nil {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            var writeError: Error?
            
            // For drawings, we want to ensure we have exclusive access
            let options: NSFileCoordinator.WritingOptions = url.pathExtension == "drawing" ? 
                [.forReplacing, .forDeleting, .forMerging] : [.forReplacing, .forDeleting]
            
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordError) { targetURL in
                do {
                    // Ensure parent directory exists in iCloud
                    let parentDir = targetURL.deletingLastPathComponent()
                    if !fm.fileExists(atPath: parentDir.path) {
                        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }
                    
                    // Check if file is already in iCloud
                    var isUbiquitous: AnyObject?
                    try? (targetURL as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                    let isInICloud = (isUbiquitous as? Bool) == true
                    
                    if isInICloud {
                        // If already in iCloud, just write the data
                        print("📝 File already in iCloud, updating content: \(url.lastPathComponent)")
                        try data.write(to: targetURL, options: [.atomic, .completeFileProtection])
                        
                        // For drawings, ensure iCloud picks up the change
                        if url.pathExtension == "drawing" {
                            try fm.startDownloadingUbiquitousItem(at: targetURL)
                        }
                    } else {
                        // If not in iCloud, need to create new file and mark for sync
                        print("📝 Creating new file in iCloud: \(url.lastPathComponent)")
                        
                        // Create a temporary file
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try data.write(to: tempURL, options: [.atomic, .completeFileProtection])
                        
                        // Move to iCloud with explicit sync for drawings
                        try fm.setUbiquitous(true, itemAt: tempURL, destinationURL: targetURL)
                        if url.pathExtension == "drawing" {
                            try fm.startDownloadingUbiquitousItem(at: targetURL)
                        }
                    }
                    
                    print("📝 Successfully wrote data to: \(url.lastPathComponent)")
                } catch {
                    print("📝 Error writing data: \(error)")
                    writeError = error
                }
            }
            
            if let error = coordError ?? writeError {
                print("📝 Error during write: \(error)")
                throw error
            }
        } else {
            do {
                // Ensure parent directory exists
                let parentDir = url.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                print("📝 Successfully wrote data locally: \(url.lastPathComponent)")
            } catch {
                print("📝 Error writing data locally: \(error)")
                throw error
            }
        }
    }

    // MARK: - Delete All Journal Data
    /// Delete all journal data including drawings, photos, and background PDFs
    func deleteAllJournalData() {
        let fm = FileManager.default
        
        // Delete all drawings
        let drawingsDir = drawingsDirectory
        if fm.fileExists(atPath: drawingsDir.path) {
            try? fm.removeItem(at: drawingsDir)
        }
        
        // Delete all photos and metadata
        let photosDir = photosDirectoryURL
        if fm.fileExists(atPath: photosDir.path) {
            try? fm.removeItem(at: photosDir)
        }
        
        // Delete background PDFs
        clearBackgroundPDF(layoutType: .compact)
        clearBackgroundPDF(layoutType: .expanded)
        
        // Clear UserDefaults journal-related keys
        let journalKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { 
            $0.contains("journal") || $0.contains("Journal") 
        }
        for key in journalKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Also clear from iCloud if available
        if let iCloudRoot = ubiquityDocsURL {
            let iCloudDrawingsDir = iCloudRoot.appendingPathComponent("journal_drawings")
            try? fm.removeItem(at: iCloudDrawingsDir)
            
            let iCloudPhotosDir = iCloudRoot.appendingPathComponent("journal_photos")
            try? fm.removeItem(at: iCloudPhotosDir)
        }
    }

    // MARK: - Types
    /// Minimal info needed from photo metadata for CloudKit attachment mapping
    struct LitePhotoMeta: Codable {
        let id: String
        let fileName: String
    }
} 