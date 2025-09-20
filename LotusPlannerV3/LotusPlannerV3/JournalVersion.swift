import Foundation

struct JournalVersion: Codable {
    let timestamp: Date
    let deviceId: String
    let version: Int
    let fileName: String
    
    var versionFileName: String {
        return fileName.replacingOccurrences(of: ".drawing", with: "_v\(version).drawing")
    }
}

struct JournalVersionManager {
    private let versionsDirectory: URL
    
    init(baseURL: URL) {
        self.versionsDirectory = baseURL.appendingPathComponent("versions")
        try? FileManager.default.createDirectory(at: versionsDirectory, withIntermediateDirectories: true)
    }
    
    func getCurrentVersion(for fileName: String) -> Int {
        let prefix = fileName.replacingOccurrences(of: ".drawing", with: "_v")
        let versions = try? FileManager.default.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: nil)
        
        return versions?
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .compactMap { URL -> Int? in
                let versionStr = URL.lastPathComponent.replacingOccurrences(of: prefix, with: "")
                    .replacingOccurrences(of: ".drawing", with: "")
                return Int(versionStr)
            }
            .max() ?? 0
    }
    
    func saveVersion(_ version: JournalVersion, data: Data) throws {
        let versionURL = versionsDirectory.appendingPathComponent(version.versionFileName)
        try data.write(to: versionURL)
        
        // Save version metadata
        let metadataURL = versionURL.appendingPathExtension("metadata")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(version)
        try metadataData.write(to: metadataURL)
    }
    
    func getVersions(for fileName: String) -> [JournalVersion] {
        let prefix = fileName.replacingOccurrences(of: ".drawing", with: "_v")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "metadata" }
            .compactMap { url -> JournalVersion? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try? decoder.decode(JournalVersion.self, from: data)
            }
            .sorted { $0.version > $1.version }
    }
    
    func getVersionData(_ version: JournalVersion) -> Data? {
        let versionURL = versionsDirectory.appendingPathComponent(version.versionFileName)
        return try? Data(contentsOf: versionURL)
    }
    
    func cleanupOldVersions(for fileName: String, keepCount: Int = 5) {
        let versions = getVersions(for: fileName)
        guard versions.count > keepCount else { return }
        
        let versionsToDelete = versions[keepCount...]
        for version in versionsToDelete {
            let versionURL = versionsDirectory.appendingPathComponent(version.versionFileName)
            let metadataURL = versionURL.appendingPathExtension("metadata")
            try? FileManager.default.removeItem(at: versionURL)
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }
}
