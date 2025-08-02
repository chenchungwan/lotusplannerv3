import SwiftUI
import Foundation

// MARK: - Data Manager
@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // Shared ViewModels
    let calendarViewModel = CalendarViewModel()
    let tasksViewModel = TasksViewModel()
    
    // Global loading state
    @Published var isInitializing = true
    
    private init() {
        // Initialize shared data on startup
        Task {
            await initializeData()
        }
        
        // Setup background preloading when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.preloadAdjacentMonths(around: Date())
            }
        }
    }
    
    private func initializeData() async {
        // Load initial calendar data for current month
        await calendarViewModel.loadCalendarDataForMonth(containing: Date())
        
        // Load tasks data
        await tasksViewModel.loadTasks()
        
        isInitializing = false
    }
    
    func preloadAdjacentMonths(around date: Date) async {
        await calendarViewModel.preloadAdjacentMonths(around: date)
    }
}