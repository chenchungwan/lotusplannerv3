import Foundation
import SwiftUI
import PencilKit

class JournalSyncCoordinator: ObservableObject {
    static let shared = JournalSyncCoordinator()
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var progress: Double = 0
    private var pendingChanges: Set<URL> = []
    private var syncTimer: Timer?
    private var batchTimer: Timer?
    private var currentBatch: Set<URL> = []
    private let batchSize = 5
    private let batchInterval: TimeInterval = 10 // seconds
    
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
        startBatchTimer()
    }
    
    private func startPeriodicSync() {
        // Sync every 5 minutes for non-drawing files
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkAndSync(forceBatch: true)
        }
    }
    
    private func startBatchTimer() {
        // Process batches every 10 seconds
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: true) { [weak self] _ in
            self?.processBatch()
        }
    }
    
    private func processBatch() {
        guard !pendingChanges.isEmpty else { return }
        
        // Take up to batchSize items
        let batch = Set(pendingChanges.prefix(batchSize))
        currentBatch = batch
        pendingChanges.subtract(batch)
        
        Task {
            await sync(urls: batch)
        }
    }
    
    func addPendingChange(_ url: URL) {
        if url.pathExtension == "drawing" {
            // For drawings, add to current batch if not full, otherwise to pending changes
            if currentBatch.count < batchSize {
                currentBatch.insert(url)
                Task {
                    await sync(urls: currentBatch)
                }
            } else {
                pendingChanges.insert(url)
            }
        } else {
            pendingChanges.insert(url)
        }
    }
    
    func checkAndSync(forceBatch: Bool = false) {
        guard syncStatus != .syncing else { return }
        
        Task {
            if forceBatch {
                // Force sync all pending changes
                let allChanges = pendingChanges.union(currentBatch)
                pendingChanges.removeAll()
                currentBatch.removeAll()
                await sync(urls: allChanges)
            } else {
                await sync(urls: currentBatch)
            }
        }
    }
    
    @MainActor
    private func sync(urls: Set<URL>) async {
        guard !urls.isEmpty else { return }
        
        syncStatus = .syncing
        progress = 0
        
        // Notify sync started
        NotificationCenter.default.post(name: .journalDrawingSyncStarted, object: nil)
        
        do {
            let total = Double(urls.count)
            var completed = 0.0
            var failedURLs: Set<URL> = []
            
            // Sort URLs to prioritize drawings
            let sortedChanges = urls.sorted { url1, url2 in
                if url1.pathExtension == "drawing" && url2.pathExtension != "drawing" {
                    return true
                }
                return false
            }
            
            // Create parallel tasks for each file
            await withTaskGroup(of: (URL, Bool).self) { group in
                for url in sortedChanges {
                    group.addTask { [self] in
                        do {
                            try await self.syncFile(at: url)
                            return (url, true)
                        } catch {
                            print("📝 Failed to sync \(url.lastPathComponent): \(error)")
                            return (url, false)
                        }
                    }
                }
                
                // Process results as they complete
                for await (url, success) in group {
                    completed += 1
                    progress = completed / total
                    
                    if success {
                        // Post specific notification for drawings
                        if url.pathExtension == "drawing" {
                            NotificationCenter.default.post(name: .journalDrawingChanged, object: nil, userInfo: ["url": url])
                        }
                    } else {
                        failedURLs.insert(url)
                    }
                }
            }
            
            // Handle failed files
            if !failedURLs.isEmpty {
                // Add failed files back to pending changes
                pendingChanges.formUnion(failedURLs)
                
                // Post partial success notification
                NotificationCenter.default.post(name: .journalDrawingSyncPartialSuccess, object: nil, 
                    userInfo: ["failedCount": failedURLs.count])
                
                syncStatus = .error("Some files failed to sync")
            } else {
                // All files synced successfully
                syncStatus = .idle
                progress = 1.0
                
                // Notify sync completed
                NotificationCenter.default.post(name: .journalDrawingSyncCompleted, object: nil)
                NotificationCenter.default.post(name: .journalContentChanged, object: nil)
            }
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("📝 Sync error: \(error)")
            
            // Add all files back to pending changes
            pendingChanges.formUnion(urls)
            
            // Notify sync failed
            NotificationCenter.default.post(name: .journalDrawingSyncFailed, object: nil, userInfo: ["error": error])
        }
    }
    
    private func syncFile(at url: URL) async throws {
        // Ensure file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            pendingChanges.remove(url)
            return
        }
        
        // Maximum number of retries for drawings
        let maxRetries = url.pathExtension == "drawing" ? 3 : 1
        var retryCount = 0
        var lastError: Error?
        
        while retryCount < maxRetries {
            do {
                // Use file coordinator for safe access
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var error: NSError?
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    coordinator.coordinate(readingItemAt: url, options: [], error: &error) { url in
                        do {
                            // Get file data
                            let data = try Data(contentsOf: url)
                            
                            // Write to iCloud with coordination
                            if let iCloudRoot = JournalManager.shared.getICloudDocsURL() {
                                // Maintain directory structure
                                let relativePath = url.deletingLastPathComponent().lastPathComponent
                                let iCloudURL = iCloudRoot.appendingPathComponent(relativePath).appendingPathComponent(url.lastPathComponent)
                                
                                // Ensure directory exists
                                let iCloudDir = iCloudURL.deletingLastPathComponent()
                                try? FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
                                
                                try JournalManager.shared.writeData(data, to: iCloudURL)
                                
                                // For drawings, verify the file exists in iCloud
                                if url.pathExtension == "drawing" {
                                    var isUbiquitous: AnyObject?
                                    try? (iCloudURL as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                                    let isInICloud = (isUbiquitous as? Bool) == true
                                    
                                    if !isInICloud {
                                        throw NSError(domain: "JournalSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "File not found in iCloud after sync"])
                                    }
                                    
                                    // Start download to ensure it's available on this device
                                    try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
                                }
                            }
                            
                            continuation.resume()
                            return
                        } catch {
                            print("📝 Error syncing file (attempt \(retryCount + 1)): \(error)")
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                if let error = error {
                    throw error
                }
                
                // If we get here, sync was successful
                return
                
            } catch {
                lastError = error
                retryCount += 1
                
                if retryCount < maxRetries {
                    // Wait before retrying (exponential backoff)
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000)
                }
            }
        }
        
        // If we get here, all retries failed
        if let error = lastError {
            throw error
        }
    }
    
    func forceSync() {
        Task {
            let allChanges = pendingChanges.union(currentBatch)
            await self.sync(urls: allChanges)
        }
    }
}

extension Notification.Name {
    static let journalContentChanged = Notification.Name("journalContentChanged")
    static let journalDrawingChanged = Notification.Name("journalDrawingChanged")
    static let journalDrawingSyncStarted = Notification.Name("journalDrawingSyncStarted")
    static let journalDrawingSyncCompleted = Notification.Name("journalDrawingSyncCompleted")
    static let journalDrawingSyncFailed = Notification.Name("journalDrawingSyncFailed")
    static let journalDrawingSyncPartialSuccess = Notification.Name("journalDrawingSyncPartialSuccess")
}
