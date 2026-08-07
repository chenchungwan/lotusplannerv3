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
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @StateObject private var weeklyBulkEditManager = BulkEditManager()
    @StateObject private var timeboxBulkEditManager = BulkEditManager()

    var body: some View {
        NavigationStack {
            currentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .sheet(item: $navigationManager.activeSheet, onDismiss: {
            navigationManager.dismissActiveSheet()
        }) { sheet in
            globalSheet(for: sheet)
        }
        // Log edit sheet attached at ContentView scope so it presents
        // regardless of which subview (Day, Week, Tasks, Lists, Goals,
        // Journal, etc.) is currently active. CalendarView previously hosted
        // it but is only mounted for the day-interval calendar mode, so the
        // popup silently queued until the user navigated back to D view.
        // (Log *creation* goes through `activeSheet` / `CreateItemSheet`.)
        .sheet(isPresented: $logsViewModel.showingEditLogSheet) {
            EditLogEntryView(viewModel: logsViewModel)
        }
    }

    @ViewBuilder
    private func globalSheet(for sheet: NavigationManager.AppSheet) -> some View {
        // All create flows share one window so the user can switch item type
        // from the tab strip instead of dismissing and reopening.
        if let kind = sheet.createItemKind {
            CreateItemSheet(initialKind: kind)
        } else {
            otherGlobalSheet(for: sheet)
        }
    }

    @ViewBuilder
    private func otherGlobalSheet(for sheet: NavigationManager.AppSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()

        case .integrations:
            IntegrationsView()

        case .about:
            AboutView()

        case .diagnostics:
            DiagnosticsView()

        case .reportIssues:
            ReportIssuesView()

        case .datePicker:
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $navigationManager.datePickerSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            navigationManager.dismissActiveSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if navigationManager.showTasksView && navigationManager.showingAllTasks {
                                navigationManager.updateInterval(.year, date: navigationManager.datePickerSelection)
                            } else {
                                navigationManager.updateInterval(navigationManager.currentInterval, date: navigationManager.datePickerSelection)
                            }
                            navigationManager.dismissActiveSheet()
                        }
                    }
                }
            }
            .presentationDetents([.large])

        case .aiTaskEntry:
            let account1Linked = auth.isLinked(kind: .account1)
            let defaultAccount: GoogleAuthManager.AccountKind = account1Linked ? .account1 : .account2
            AITaskEntryView(
                tasksViewModel: tasksVM,
                authManager: auth,
                appPrefs: appPrefs,
                defaultAccountKind: defaultAccount
            )

        // Create flows are handled by `globalSheet(for:)` above.
        case .addEvent, .addTask, .addList, .addGoal, .addLog:
            EmptyView()
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
