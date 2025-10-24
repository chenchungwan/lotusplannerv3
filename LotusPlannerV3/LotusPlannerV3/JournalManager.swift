import Foundation
import UniformTypeIdentifiers
import PencilKit
#if canImport(UIKit)
import UIKit
#endif

/// Layout type for journal views
enum JournalLayoutType {
    case compact
    case expanded
}

/// Handles storage & retrieval of the journal background PDF and photo management.
class JournalManager: NSObject {
    static let shared = JournalManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Document URLs
    
    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var ubiquityDocsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }
    
    // MARK: - Photo Management (iCloud-first like drawings)
    
    private var iCloudPhotosURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("journal_photos")
    }
    
    var localPhotosURL: URL {
        docsURL.appendingPathComponent("journal_photos")
    }
    
    var photosDirectoryURL: URL {
        // Use iCloud first, fallback to local
        if let iCloudURL = iCloudPhotosURL {
            if !FileManager.default.fileExists(atPath: iCloudURL.path) {
                try? FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
            }
            return iCloudURL
        } else {
            let dir = localPhotosURL
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
    }
    
    func metadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_photos.json"
        return photosDirectoryURL.appendingPathComponent(name)
    }
    
    // MARK: - Background PDF Management
    
    private func storedURL(for layoutType: JournalLayoutType) -> URL {
        let filename = layoutType == .compact ? "journal_background_compact.pdf" : "journal_background_expanded.pdf"
        return docsURL.appendingPathComponent(filename)
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
    
    // MARK: - Delete All Journal Data
    
    /// Delete all journal data including drawings, photos, and background PDFs
    func deleteAllJournalData() {
        let fm = FileManager.default
        
        // Delete all drawings (using new storage system)
        if let iCloudRoot = ubiquityDocsURL {
            let iCloudDrawingsDir = iCloudRoot.appendingPathComponent("journal_drawings")
            try? fm.removeItem(at: iCloudDrawingsDir)
        }
        
        // Delete local drawings directory
        let localDrawingsDir = docsURL.appendingPathComponent("journal_drawings")
        if fm.fileExists(atPath: localDrawingsDir.path) {
            try? fm.removeItem(at: localDrawingsDir)
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
            let iCloudPhotosDir = iCloudRoot.appendingPathComponent("journal_photos")
            try? fm.removeItem(at: iCloudPhotosDir)
        }
    }
}