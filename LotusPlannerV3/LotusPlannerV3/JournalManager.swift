import Foundation
import UniformTypeIdentifiers
import PencilKit

/// Handles storage & retrieval of the journal background PDF inside the app sandbox.
struct JournalManager {
    static let shared = JournalManager()
    private init() {}
    
    private let fileName = "journal_background.pdf"
    
    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    private var storedURL: URL { docsURL.appendingPathComponent(fileName) }
    
    /// Save/copy a PDF from a temporary location into Documents, overwriting any previous file.
    func savePDF(from sourceURL: URL) throws {
        // Remove old
        try? FileManager.default.removeItem(at: storedURL)
        try FileManager.default.copyItem(at: sourceURL, to: storedURL)
        // Persist path
        UserDefaults.standard.set(storedURL.path, forKey: "journalBackgroundPDFPath")
    }

    /// Save raw PDF data (if we can't copy directly due to sandbox restrictions)
    func savePDF(data: Data) throws {
        try? FileManager.default.removeItem(at: storedURL)
        try data.write(to: storedURL, options: .atomic)
        UserDefaults.standard.set(storedURL.path, forKey: "journalBackgroundPDFPath")
    }
    
    /// URL to the stored PDF if it exists.
    var backgroundPDFURL: URL? {
        if FileManager.default.fileExists(atPath: storedURL.path) {
            return storedURL
        }
        if let path = UserDefaults.standard.string(forKey: "journalBackgroundPDFPath") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) { return url }
        }
        return nil
    }
    
    /// Load PDF data if available.
    func loadPDFData() -> Data? {
        guard let url = backgroundPDFURL else { return nil }
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