//
//  ContentView.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI



struct ContentView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @StateObject private var appPrefs = AppPreferences.shared

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
                    WeeklyView()
                        .id("WeeklyView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
                } else {
                    CalendarView()
                        .id("CalendarView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
                }
            }
        case .tasks:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                // Use WeeklyView for weekly task-focused view, CalendarView for daily events
                if navigationManager.currentInterval == .week {
                    WeeklyView()
                        .id("WeeklyView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
                } else {
                    CalendarView()
                        .id("CalendarView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
                }
            }
        
        case .lists:
            ListsView()
        
        case .goals:
            if !appPrefs.hideGoals {
                GoalsView()
            } else {
                // Fallback to calendar view when goals are hidden
                CalendarView()
                    .id("CalendarView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
            }

        case .journal:
                JournalView(currentDate: Date())
            case .weeklyView:
                WeeklyView()
            case .gWeekView:
                CalendarView()
            case .yearlyCalendar:
                CalendarYearlyView()
                    .id("CalendarYearlyView-\(navigationManager.currentDate)-\(navigationManager.currentInterval)")
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
