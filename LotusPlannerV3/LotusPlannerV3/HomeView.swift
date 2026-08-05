//
//  ContentView.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI



struct ContentView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var logsViewModel = LogsViewModel.shared
    @StateObject private var weeklyBulkEditManager = BulkEditManager()
    @StateObject private var timeboxBulkEditManager = BulkEditManager()

    var body: some View {
        NavigationStack {
            currentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $navigationManager.showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $navigationManager.showingIntegrations) {
            IntegrationsView()
        }
        // Log sheets attached at ContentView scope so they present regardless
        // of which subview (Day, Week, Tasks, Lists, Goals, Journal, etc.) is
        // currently active. CalendarView previously hosted these but is only
        // mounted for the day-interval calendar mode, so the popups silently
        // queued until the user navigated back to D view.
        .sheet(isPresented: $logsViewModel.showingAddLogSheet) {
            AddLogEntryView(viewModel: logsViewModel)
        }
        .sheet(isPresented: $logsViewModel.showingEditLogSheet) {
            EditLogEntryView(viewModel: logsViewModel)
        }
    }

    @ViewBuilder
    private var currentView: some View {
        switch navigationManager.currentView {
        case .calendar:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                // Use WeeklyView for weekly task-focused view, CalendarView for daily events
                if navigationManager.currentInterval == .week {
                    WeeklyView(bulkEditManager: weeklyBulkEditManager)
                } else {
                    CalendarView()
                }
            }
        case .tasks:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                // Use WeeklyView for weekly task-focused view, CalendarView for daily events
                if navigationManager.currentInterval == .week {
                    WeeklyView(bulkEditManager: weeklyBulkEditManager)
                } else {
                    CalendarView()
                }
            }
        
        case .lists:
            ListsView()
        
        case .goals:
            if !appPrefs.hideGoals {
                GoalsView()
            } else {
                CalendarView()
            }
        
        case .journal:
                JournalView(currentDate: .constant(Date()))
            case .journalDayViews:
                JournalDayViews()
            case .weeklyView:
                WeeklyView(bulkEditManager: weeklyBulkEditManager)
            case .gWeekView:
                CalendarView()
            case .yearlyCalendar:
                CalendarYearlyView()
            case .timebox:
                TimeboxView(bulkEditManager: timeboxBulkEditManager)
                    .id("TimeboxView-\(navigationManager.viewRefreshCounter)")
            case .bookView:
                BookView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
