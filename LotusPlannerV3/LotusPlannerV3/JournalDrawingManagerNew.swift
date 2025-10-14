import Foundation
import PencilKit
import SwiftUI

/// Simple drawing manager with debouncing - no complex retry logic
@MainActor
class JournalDrawingManagerNew: ObservableObject {
    static let shared = JournalDrawingManagerNew()
    
    @Published private(set) var isSaving = false
    @Published private(set) var lastSaveError: String?
    
    private var saveTask: Task<Void, Never>?
    private var pendingDrawing: (date: Date, drawing: PKDrawing)?
    
    // Save after 1 second of no changes
    private let debounceDelay: TimeInterval = 1.0
    
    private init() {
        print("📝 JournalDrawingManagerNew initialized")
        
        // Save on app background
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.saveImmediately()
            }
        }
    }
    
    /// Called when user draws - debounces the save
    func handleDrawingChange(date: Date, drawing: PKDrawing) {
        // Store the latest drawing
        pendingDrawing = (date, drawing)
        
        // Cancel existing save task
        saveTask?.cancel()
        
        // Schedule new save
        saveTask = Task {
            do {
                // Wait for debounce
                try await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
                
                // Save if not cancelled
                if !Task.isCancelled {
                    await performSave()
                }
            } catch {
                // Task was cancelled, that's okay
            }
        }
    }
    
    /// Save immediately (called when switching dates or backgrounding)
    func saveImmediately() async {
        saveTask?.cancel()
        await performSave()
    }
    
    /// Actually perform the save
    private func performSave() async {
        guard let pending = pendingDrawing else { return }
        
        isSaving = true
        lastSaveError = nil
        
        do {
            try await JournalStorageNew.shared.save(pending.drawing, for: pending.date)
            pendingDrawing = nil
            print("✅ Drawing saved successfully")
        } catch {
            lastSaveError = error.localizedDescription
            print("❌ Save failed: \(error.localizedDescription)")
        }
        
        isSaving = false
    }
    
    /// Called when switching to a different date
    func willSwitchDate() async {
        await saveImmediately()
    }
}

