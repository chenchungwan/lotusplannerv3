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
struct JournalManager {
    static let shared = JournalManager()
    private init() {}
    private static var metadataQuery: NSMetadataQuery?
    
    // MARK: - Storage roots
    /// iCloud Drive Documents directory for the app (if available)
    private var ubiquityDocsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
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
        ubiquityDocsURL ?? localDocsURL
    }

    /// Expose the current storage root for other components (e.g. photos)
    func storageRootURL() -> URL { docsURL }

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
        // Use UTC so filenames are consistent across devices/timezones
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + ".drawing"
        return drawingsDirectory.appendingPathComponent(name)
    }

    func saveDrawing(for date: Date, drawing: PKDrawing) {
        let data = drawing.dataRepresentation()
        let url = drawingURL(for: date)
        writeData(data, to: url)
        // If iCloud becomes available later, move local files automatically
        migrateLocalToICloudIfNeeded()
    }
    
    func loadDrawing(for date: Date) -> PKDrawing? {
        let url = drawingURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let drawing = try? PKDrawing(data: data) {
            return drawing
        }
        // If not found at current root, try the other root (fallback) to bridge gaps
        if let iCloudRoot = ubiquityDocsURL {
            let altURL = iCloudRoot.appendingPathComponent("journal_drawings").appendingPathComponent(url.lastPathComponent)
            if let data = try? Data(contentsOf: altURL), let drawing = try? PKDrawing(data: data) {
                return drawing
            }
        }
        let altLocal = localDocsURL.appendingPathComponent("journal_drawings").appendingPathComponent(url.lastPathComponent)
        if let data = try? Data(contentsOf: altLocal), let drawing = try? PKDrawing(data: data) {
            return drawing
        }
        return nil
    }

    // MARK: - iCloud Monitoring / Download
    /// Start monitoring the iCloud Documents scope for journal files and trigger downloads.
    func startICloudMonitoring() {
        guard ubiquityDocsURL != nil else { return }
        if JournalManager.metadataQuery != nil { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "(kMDItemFSName LIKE[c] '*.drawing') OR (kMDItemFSName LIKE[c] '*_photos.json') OR (kMDItemFSName LIKE[c] '*.png')")

        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in
            self.downloadAllResults(query)
            NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
            query.enableUpdates()
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { _ in
            self.downloadAllResults(query)
            NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
        }
        JournalManager.metadataQuery = query
        query.start()
    }


    func stopICloudMonitoring() {
        guard let query = JournalManager.metadataQuery else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        JournalManager.metadataQuery = nil
    }

    private func downloadAllResults(_ query: NSMetadataQuery) {
        let fm = FileManager.default
        for item in query.results {
            guard let result = item as? NSMetadataItem,
                  let url = result.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            var isUbiq: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiq, forKey: URLResourceKey.isUbiquitousItemKey)
            if (isUbiq as? Bool) == true {
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
        }
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
    func writeData(_ data: Data, to url: URL) {
        if ubiquityDocsURL != nil {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { targetURL in
                try? data.write(to: targetURL, options: .atomic)
            }
            if coordError != nil {
                try? data.write(to: url, options: .atomic)
            }
        } else {
            try? data.write(to: url, options: .atomic)
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