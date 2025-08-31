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
        // Only load data if accounts are linked to avoid unnecessary error alerts
        let authManager = GoogleAuthManager.shared
        
        // Load initial calendar data for current month only if accounts are linked
        if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
            await calendarViewModel.loadCalendarDataForMonth(containing: Date())
        }
        
        // Load tasks data only if accounts are linked
        if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
            await tasksViewModel.loadTasks()
        }
        
        isInitializing = false
    }
    
    func preloadAdjacentMonths(around date: Date) async {
        await calendarViewModel.preloadAdjacentMonths(around: date)
    }
}