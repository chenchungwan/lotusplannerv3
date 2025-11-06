import Foundation
import SwiftUI

/// Background processing system for heavy operations
@MainActor
class BackgroundProcessor: ObservableObject {
    static let shared = BackgroundProcessor()
    
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentOperation: String = ""
    
    private var backgroundTasks: [String: Task<Void, Never>] = [:]
    private let maxConcurrentTasks = 3
    
    private init() {}
    
    /// Process heavy operation in background with progress tracking
    func processInBackground<T>(
        id: String,
        operation: String,
        priority: TaskPriority = .background,
        work: @escaping () async throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        // Cancel existing task with same ID
        backgroundTasks[id]?.cancel()
        
        // Create new background task
        let task = Task(priority: priority) {
            do {
                await MainActor.run {
                    self.isProcessing = true
                    self.currentOperation = operation
                    self.progress = 0.0
                }
                
                let result = try await work()
                
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 1.0
                    self.currentOperation = ""
                }
                
                completion(.success(result))
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 0.0
                    self.currentOperation = ""
                }
                
                completion(.failure(error))
            }
        }
        
        backgroundTasks[id] = task
    }
    
    /// Process multiple operations in parallel with progress tracking
    func processBatchInBackground<T>(
        id: String,
        operation: String,
        items: [T],
        batchSize: Int = 10,
        priority: TaskPriority = .background,
        work: @escaping (T) async throws -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        backgroundTasks[id]?.cancel()
        
        let task = Task(priority: priority) {
            do {
                await MainActor.run {
                    self.isProcessing = true
                    self.currentOperation = operation
                    self.progress = 0.0
                }
                
                let totalItems = items.count
                var processedItems = 0
                
                // Process items in batches
                for batchStart in stride(from: 0, to: totalItems, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, totalItems)
                    let batch = Array(items[batchStart..<batchEnd])
                    
                    // Process batch in parallel
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for item in batch {
                            group.addTask {
                                try await work(item)
                            }
                        }
                        
                        try await group.waitForAll()
                    }
                    
                    processedItems += batch.count
                    
                    // Update progress
                    await MainActor.run {
                        self.progress = Double(processedItems) / Double(totalItems)
                    }
                }
                
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 1.0
                    self.currentOperation = ""
                }
                
                completion(.success(()))
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 0.0
                    self.currentOperation = ""
                }
                
                completion(.failure(error))
            }
        }
        
        backgroundTasks[id] = task
    }
    
    /// Cancel specific background task
    func cancelTask(id: String) {
        backgroundTasks[id]?.cancel()
        backgroundTasks.removeValue(forKey: id)
    }
    
    /// Cancel all background tasks
    func cancelAllTasks() {
        for task in backgroundTasks.values {
            task.cancel()
        }
        backgroundTasks.removeAll()
    }
    
    /// Check if specific task is running
    func isTaskRunning(id: String) -> Bool {
        guard let task = backgroundTasks[id] else { return false }
        return !task.isCancelled
    }
}

/// Background processing view modifier
struct BackgroundProcessingModifier: ViewModifier {
    @StateObject private var processor = BackgroundProcessor.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if processor.isProcessing {
                    VStack(spacing: 8) {
                        HStack {
                            ProgressView(value: processor.progress)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text("\(Int(processor.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(processor.currentOperation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding()
                }
            }
    }
}

extension View {
    /// Add background processing indicator to any view
    func backgroundProcessing() -> some View {
        modifier(BackgroundProcessingModifier())
    }
}

/// Example usage for heavy operations
extension BackgroundProcessor {
    
    /// Process photos in background
    func processPhotosInBackground<T>(
        photos: [T],
        operation: @escaping (T) async throws -> Void
    ) {
        processBatchInBackground(
            id: "photo_processing",
            operation: "Processing photos",
            items: photos,
            batchSize: 5,
            work: operation
        ) { result in
            switch result {
            case .success:
                logPerformance("Photo processing completed successfully")
            case .failure(let error):
                logError("Photo processing failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Process calendar events in background
    func processEventsInBackground(
        events: [GoogleCalendarEvent],
        operation: @escaping (GoogleCalendarEvent) async throws -> Void
    ) {
        processBatchInBackground(
            id: "event_processing",
            operation: "Processing calendar events",
            items: events,
            batchSize: 10,
            work: operation
        ) { result in
            switch result {
            case .success:
                logPerformance("Event processing completed successfully")
            case .failure(let error):
                logError("Event processing failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Process tasks in background
    func processTasksInBackground(
        tasks: [GoogleTask],
        operation: @escaping (GoogleTask) async throws -> Void
    ) {
        processBatchInBackground(
            id: "task_processing",
            operation: "Processing tasks",
            items: tasks,
            batchSize: 20,
            work: operation
        ) { result in
            switch result {
            case .success:
                logPerformance("Task processing completed successfully")
            case .failure(let error):
                logError("Task processing failed: \(error.localizedDescription)")
            }
        }
    }
}
