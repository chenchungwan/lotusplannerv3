//
//  ContentView.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI



struct ContentView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared

    var body: some View {
        NavigationStack {
            currentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                    WeeklyView()
                } else {
                    CalendarView()
                }
            }

        case .journal:
            JournalView(currentDate: Date())
        case .weeklyView:
            WeeklyView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
