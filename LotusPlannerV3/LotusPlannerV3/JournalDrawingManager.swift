import Foundation
import PencilKit
import SwiftUI

@MainActor
class JournalDrawingManager: ObservableObject {
    static let shared = JournalDrawingManager()
    
    @Published private(set) var isDrawing = false
    @Published private(set) var isSaving = false
    @Published private(set) var lastSaveDate: Date?
    
    private var drawingDebounceTask: Task<Void, Never>?
    private var saveDebounceTask: Task<Void, Never>?
    private var activeDrawingDate: Date?
    private var unsavedChanges: [Date: PKDrawing] = [:]
    
    // Debounce times
    private let drawingDebounceTime: TimeInterval = 0.1  // Wait for drawing to stabilize
    private let saveDebounceTime: TimeInterval = 0.5     // Wait before saving
    
    private init() {
        // Register for app termination notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppTermination() {
        // Create a semaphore to wait for saves to complete
        let semaphore = DispatchSemaphore(value: 0)
        
        Task { @MainActor in
            // Cancel any pending tasks
            drawingDebounceTask?.cancel()
            saveDebounceTask?.cancel()
            
            // Save all unsaved changes immediately
            for (date, drawing) in unsavedChanges {
                do {
                    // Save directly without debouncing
                    try await JournalManager.shared.saveDrawingAsync(for: date, drawing: drawing)
                    print("📝 Successfully saved drawing for \(date) during app termination")
                } catch {
                    print("📝 Failed to save drawing for \(date) during app termination: \(error)")
                }
            }
            
            semaphore.signal()
        }
        
        // Wait for saves to complete (timeout after 2 seconds)
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
    
    func handleDrawingChange(date: Date, drawing: PKDrawing) {
        // Immediately cache the drawing to prevent visual disappearance
        JournalCache.shared.cacheDrawing(drawing, for: date)
        
        // Cancel any pending debounce task
        drawingDebounceTask?.cancel()
        
        // Start new debounce task
        drawingDebounceTask = Task {
            isDrawing = true
            activeDrawingDate = date
            
            // Store unsaved changes immediately
            unsavedChanges[date] = drawing
            
            // Wait for drawing to stabilize
            try? await Task.sleep(nanoseconds: UInt64(drawingDebounceTime * 1_000_000_000))
            
            // Check if task was cancelled
            if !Task.isCancelled {
                // Start save debounce
                await debounceSave(date: date)
            }
            
            isDrawing = false
        }
    }
    
    private func debounceSave(date: Date) async {
        // Cancel any pending save task
        saveDebounceTask?.cancel()
        
        // Start new save task
        saveDebounceTask = Task {
            do {
                // Wait for save debounce
                try await Task<Never, Never>.sleep(nanoseconds: UInt64(saveDebounceTime * 1_000_000_000))
                
                // Check if task was cancelled
                if !Task.isCancelled {
                    // Ensure the drawing is still in unsaved changes
                    if self.unsavedChanges[date] != nil {
                        await saveChanges(for: date)
                    }
                }
            } catch {
                // Task was cancelled, ensure drawing is still cached
                if let drawing = self.unsavedChanges[date] {
                    JournalCache.shared.cacheDrawing(drawing, for: date)
                }
            }
        }
    }
    
    private func saveChanges(for date: Date) async {
        guard let drawing = unsavedChanges[date] else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            // Create save task with exponential backoff
            try await Task.retrying(maxRetryCount: 5, retryDelay: 1.0) {
                do {
                    // Save to journal manager
                    try await JournalManager.shared.saveDrawingAsync(for: date, drawing: drawing)
                    
                    // Update state
                    self.unsavedChanges.removeValue(forKey: date)
                    self.lastSaveDate = Date()
                    
                    // Post success notification
                    NotificationCenter.default.post(name: .journalDrawingSaveSucceeded, object: nil, 
                        userInfo: ["date": date])
                    
                } catch {
                    // Post error notification
                    NotificationCenter.default.post(name: .journalDrawingSaveFailed, object: nil, 
                        userInfo: ["date": date, "error": error])
                    
                    // Rethrow for retry
                    throw error
                }
            }.value
            
        } catch {
            print("📝 Failed to save drawing after all retries: \(error)")
            
            // Keep changes in unsaved state and schedule background retry
            let _ = Task<Void, Never>.detached { [weak self] in
                do {
                    try await Task<Never, Never>.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    if let self = self {
                        await self.saveChanges(for: date)
                    }
                } catch {}
            }
            
            // Post critical error notification
            NotificationCenter.default.post(name: .journalDrawingSaveCriticalError, object: nil,
                userInfo: ["date": date, "error": error])
        }
    }
    
    func willSwitchDate(from: Date, to: Date) async {
        // Save any pending changes for the old date
        if let drawing = unsavedChanges[from] {
            await saveChanges(for: from)
        }
        
        // Cancel any pending tasks
        drawingDebounceTask?.cancel()
        saveDebounceTask?.cancel()
        
        // Reset state
        isDrawing = false
        activeDrawingDate = to
    }
    
    func appWillResignActive() async {
        // Save all unsaved changes
        for (date, _) in unsavedChanges {
            await saveChanges(for: date)
        }
    }
}

// Helper for retrying tasks
extension Notification.Name {
    static let journalDrawingSaveSucceeded = Notification.Name("journalDrawingSaveSucceeded")
    static let journalDrawingSaveFailed = Notification.Name("journalDrawingSaveFailed")
    static let journalDrawingSaveCriticalError = Notification.Name("journalDrawingSaveCriticalError")
}

extension JournalDrawingManager {
    static func sleep(seconds: TimeInterval) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task<Never, Never>.sleep(nanoseconds: duration)
    }
}

extension Task where Failure == Error {
    static func retrying(
        maxRetryCount: Int,
        retryDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> Success
    ) -> Task<Success, Failure> {
        Task {
            for attempt in 0...maxRetryCount {
                do {
                    return try await operation()
                } catch {
                    if attempt == maxRetryCount {
                        throw error
                    }
                    // Calculate delay with exponential backoff
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await JournalDrawingManager.sleep(seconds: delay)
                }
            }
            throw NSError(domain: "RetryError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"])
        }
    }
}
