import SwiftUI
import Foundation

// MARK: - Data Manager
@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // Shared ViewModels
    let calendarViewModel = CalendarViewModel()
    let tasksViewModel = TasksViewModel()
    let goalsManager = GoalsManager.shared
    let customLogManager = CustomLogManager.shared
    
    // Global loading state
    @Published var isInitializing = true
    
    // MARK: - Request Debouncing
    private var debounceTimers: [String: Task<Void, Never>] = [:]
    private let debounceInterval: TimeInterval = 0.5 // 500ms
    
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
            await tasksViewModel.loadTasks()
        }
        
        isInitializing = false
    }
    
    func preloadAdjacentMonths(around date: Date) async {
        await debounce(key: "preloadAdjacentMonths") {
            await self.calendarViewModel.preloadAdjacentMonths(around: date)
        }
    }
    
    // MARK: - Debounce Helper
    private func debounce(key: String, interval: TimeInterval? = nil, action: @escaping () async -> Void) async {
        // Cancel any existing task for this key
        debounceTimers[key]?.cancel()
        
        // Create a new debounced task
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64((interval ?? debounceInterval) * 1_000_000_000))
            if !Task.isCancelled {
                await action()
            }
        }
        
        debounceTimers[key] = task
        await task.value
    }
    
    // MARK: - Background Refresh
    private func refreshCalendarDataInBackground() async {
        let authManager = GoogleAuthManager.shared
        
        // FUNCTIONALITY PRESERVED: Only refresh if accounts are actually linked
        guard authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) else {
            return
        }
        
        // Apply debouncing to prevent rapid repeated refresh calls
        await debounce(key: "refreshCalendarData", interval: 1.0) {
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
                }
            }
        }
    }
}