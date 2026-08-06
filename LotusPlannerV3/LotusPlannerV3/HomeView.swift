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
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @StateObject private var weeklyBulkEditManager = BulkEditManager()
    @StateObject private var timeboxBulkEditManager = BulkEditManager()
    @State private var newListName = ""
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?

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
    private func globalSheet(for sheet: NavigationManager.AppSheet) -> some View {
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

        case .addEvent:
            NavigationStack {
                AddItemView(
                    currentDate: navigationManager.currentDate,
                    tasksViewModel: tasksVM,
                    calendarViewModel: calendarVM,
                    appPrefs: appPrefs,
                    showEventOnly: true
                )
            }

        case .addTask:
            newTaskSheet

        case .aiTaskEntry:
            let personalLinked = auth.isLinked(kind: .personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? .personal : .professional
            AITaskEntryView(
                tasksViewModel: tasksVM,
                authManager: auth,
                appPrefs: appPrefs,
                defaultAccountKind: defaultAccount
            )

        case .addList:
            NewListSheet(
                appPrefs: appPrefs,
                accountKind: newListAccountKind,
                hasPersonal: auth.isLinked(kind: .personal),
                hasProfessional: auth.isLinked(kind: .professional),
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                listName: $newListName,
                selectedAccount: $newListAccountKind,
                onCreate: createNewList
            )
            .onAppear {
                newListName = ""
                newListAccountKind = nil
            }
        }
    }

    private var newTaskSheet: some View {
        let personalLinked = auth.isLinked(kind: .personal)
        let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? .personal : .professional
        let defaultLists = defaultAccount == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        let defaultListId = defaultLists.first?.id ?? ""
        let newTask = GoogleTask(
            id: UUID().uuidString,
            title: "",
            notes: nil,
            status: "needsAction",
            due: nil,
            completed: nil,
            updated: nil,
            position: "0"
        )

        return NavigationStack {
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksVM,
                onSave: { updatedTask in
                    Task {
                        await tasksVM.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                    }
                },
                onDelete: {},
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksVM.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                    Task {
                        await tasksVM.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                    }
                },
                isNew: true
            )
        }
    }

    private func createNewList() {
        guard let accountKind = newListAccountKind else { return }

        Task {
            let title = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
            let _ = await tasksVM.createTaskList(title: title, for: accountKind)
            await MainActor.run {
                navigationManager.dismissActiveSheet()
                newListName = ""
                newListAccountKind = nil
            }
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
