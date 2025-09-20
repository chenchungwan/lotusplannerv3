import Foundation
import SwiftUI
import PencilKit

class JournalSyncCoordinator: ObservableObject {
    static let shared = JournalSyncCoordinator()
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var progress: Double = 0
    private var pendingChanges: Set<URL> = []
    private var syncTimer: Timer?
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
        
        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.syncing, .syncing):
                return true
            case (.error(let e1), .error(let e2)):
                return e1 == e2
            default:
                return false
            }
        }
    }
    
    private init() {
        startPeriodicSync()
    }
    
    private func startPeriodicSync() {
        // Sync every 5 minutes
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkAndSync()
        }
    }
    
    func addPendingChange(_ url: URL) {
        pendingChanges.insert(url)
    }
    
    func checkAndSync() {
        guard syncStatus != .syncing else { return }
        
        Task {
            await sync()
        }
    }
    
    @MainActor
    private func sync() async {
        guard !pendingChanges.isEmpty else { return }
        
        syncStatus = .syncing
        progress = 0
        
        do {
            let total = Double(pendingChanges.count)
            var completed = 0.0
            
            for url in pendingChanges {
                try await syncFile(at: url)
                completed += 1
                progress = completed / total
            }
            
            pendingChanges.removeAll()
            syncStatus = .idle
            progress = 1.0
            
            // Notify UI
            NotificationCenter.default.post(name: .journalContentChanged, object: nil)
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("📝 Sync error: \(error)")
        }
    }
    
    private func syncFile(at url: URL) async throws {
        // Ensure file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            pendingChanges.remove(url)
            return
        }
        
        // Use file coordinator for safe access
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { url in
                do {
                    // Get file data
                    let data = try Data(contentsOf: url)
                    
                    // Write to iCloud with coordination
                    if let iCloudURL = JournalManager.shared.getICloudDocsURL()?.appendingPathComponent(url.lastPathComponent) {
                        try JournalManager.shared.writeData(data, to: iCloudURL)
                    }
                    
                    continuation.resume()
                } catch {
                    print("📝 Error syncing file: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
        
        if let error = error {
            throw error
        }
    }
    
    func forceSync() {
        Task {
            await sync()
        }
    }
}

extension Notification.Name {
    static let journalContentChanged = Notification.Name("journalContentChanged")
}
