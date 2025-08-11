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
                // Check if user prefers BaseView for weekly calendar
                if appPrefs.useBaseViewForWeekly && navigationManager.currentInterval == .week {
                    BaseView()
                } else {
                    CalendarView()
                }
            }
        case .tasks:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                // Check if user prefers BaseView for weekly calendar
                if appPrefs.useBaseViewForWeekly && navigationManager.currentInterval == .week {
                    BaseView()
                } else {
                    CalendarView()
                }
            }

        case .journal:
            JournalView(currentDate: Date())
        case .settings:
            SettingsView()
        case .base:
            BaseView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
