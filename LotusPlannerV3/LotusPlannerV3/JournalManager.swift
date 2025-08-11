import Foundation
import UniformTypeIdentifiers
import PencilKit

/// Layout type for journal views
enum JournalLayoutType {
    case compact
    case expanded
}

/// Handles storage & retrieval of the journal background PDF inside the app sandbox.
struct JournalManager {
    static let shared = JournalManager()
    private init() {}
    
    private func fileName(for layoutType: JournalLayoutType) -> String {
        return "journal_background.pdf"
    }

    // Prefer the app’s iCloud Drive container for user-generated files. If
    // iCloud is unavailable (e.g. signed-out, Simulator), fall back to the
    // local Documents directory so the feature continues to work offline.
    private var ubiquityDocsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }

    private var docsURL: URL {
        ubiquityDocsURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + ".drawing"
        return drawingsDirectory.appendingPathComponent(name)
    }

    func saveDrawing(for date: Date, drawing: PKDrawing) {
        let data = drawing.dataRepresentation()
        let url = drawingURL(for: date)
        try? data.write(to: url, options: .atomic)
    }
    
    func loadDrawing(for date: Date) -> PKDrawing? {
        let url = drawingURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PKDrawing(data: data)
    }
} 