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
                // FUNCTIONALITY PRESERVED: Same cache-only preloading behavior
                await self?.preloadAdjacentMonths(around: Date())
            }
        }
        
        // PERFORMANCE ENHANCEMENT: Background refresh when app enters foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Only refresh if accounts are linked to avoid unnecessary calls
                await self?.refreshCalendarDataInBackground()
            }
        }
    }
    
    private func initializeData() async {
        // Only load data if accounts are linked to avoid unnecessary error alerts
        let authManager = GoogleAuthManager.shared
        
        // Preload month cache only (do not mutate published arrays) if accounts are linked
        if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
            await calendarViewModel.preloadMonthIntoCache(containing: Date())
        }
        
        // Load tasks data only if accounts are linked
        if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
            print("📋 DataManager: Loading tasks during initialization...")
            await tasksViewModel.loadTasks()
            print("📋 DataManager: Tasks loading complete")
        }
        
        isInitializing = false
    }
    
    func preloadAdjacentMonths(around date: Date) async {
        await calendarViewModel.preloadAdjacentMonths(around: date)
    }
    
    // MARK: - Background Refresh
    private func refreshCalendarDataInBackground() async {
        let authManager = GoogleAuthManager.shared
        
        // FUNCTIONALITY PRESERVED: Only refresh if accounts are actually linked
        guard authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) else {
            print("📱 DataManager: No accounts linked, skipping background refresh")
            return
        }
        
        print("📱 DataManager: Starting background calendar refresh...")
        
        // Refresh current month data in background (non-blocking)
        Task.detached(priority: .background) {
            await self.calendarViewModel.preloadMonthIntoCache(containing: Date())
            
            // Preload adjacent months for smoother navigation
            let calendar = Calendar.mondayFirst
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: Date()) {
                await self.calendarViewModel.preloadMonthIntoCache(containing: prevMonth)
            }
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date()) {
                await self.calendarViewModel.preloadMonthIntoCache(containing: nextMonth)
            }
            
            await MainActor.run {
                print("✅ DataManager: Background calendar refresh completed")
            }
        }
    }
}