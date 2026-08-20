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
    @State private var isDesktopDrawerExpanded = false

    var body: some View {
        NavigationStack {
            mainContent
        }
        .background(Color(.systemBackground))
        .sheet(item: activeSheetBinding, onDismiss: {
            navigationManager.dismissActiveSheet()
        }) { sheet in
            globalSheet(for: sheet)
        }
        .fullScreenCover(isPresented: settingsFullPageBinding) {
            SettingsView()
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

    private var activeSheetBinding: Binding<NavigationManager.AppSheet?> {
        Binding(
            get: {
                navigationManager.activeSheet == .settings ? nil : navigationManager.activeSheet
            },
            set: { newValue in
                navigationManager.activeSheet = newValue
            }
        )
    }

    private var settingsFullPageBinding: Binding<Bool> {
        Binding(
            get: { navigationManager.activeSheet == .settings },
            set: { isPresented in
                if !isPresented && navigationManager.activeSheet == .settings {
                    navigationManager.dismissActiveSheet()
                }
            }
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if usesDesktopDrawer {
            HStack(spacing: 0) {
                DesktopNavigationDrawer(isExpanded: $isDesktopDrawerExpanded)
                    .frame(width: isDesktopDrawerExpanded ? 232 : 56)

                currentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
            .animation(.easeInOut(duration: 0.18), value: isDesktopDrawerExpanded)
        } else {
            currentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }

    private var usesDesktopDrawer: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif canImport(UIKit)
        return ProcessInfo.processInfo.isiOSAppOnMac
        #else
        return true
        #endif
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
            EmptyView()

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

private struct DesktopNavigationDrawer: View {
    @Binding var isExpanded: Bool
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            VStack(spacing: 4) {
                drawerButton(
                    title: "Calendar",
                    systemImage: "calendar",
                    isSelected: isCalendarSelected
                ) {
                    navigationManager.switchToCalendar()
                }

                drawerButton(
                    title: "Tasks",
                    systemImage: "checklist",
                    isSelected: navigationManager.currentView == .tasks
                ) {
                    navigationManager.switchToTasks()
                }

                drawerButton(
                    title: "Lists",
                    systemImage: "list.bullet",
                    isSelected: navigationManager.currentView == .lists
                ) {
                    navigationManager.switchToLists()
                }

                drawerButton(
                    title: "Journals",
                    systemImage: "book",
                    isSelected: navigationManager.currentView == .journalDayViews
                ) {
                    navigationManager.switchToJournalDayViews()
                }

                if !appPrefs.hideBookView {
                    drawerButton(
                        title: "Book View (Beta)",
                        systemImage: "book.pages",
                        isSelected: navigationManager.currentView == .bookView
                    ) {
                        navigationManager.switchToBookView()
                    }
                }

                if !appPrefs.hideGoals {
                    drawerButton(
                        title: "Goals",
                        systemImage: "target",
                        isSelected: navigationManager.currentView == .goals
                    ) {
                        navigationManager.switchToGoals()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                drawerButton(title: "Settings", systemImage: "gearshape") {
                    navigationManager.present(.settings)
                }

                drawerButton(title: "Integrations", systemImage: "puzzlepiece.extension") {
                    navigationManager.present(.integrations)
                }

                drawerButton(title: "About", systemImage: "info.circle") {
                    navigationManager.present(.about)
                }

                drawerButton(title: "Diagnostics", systemImage: "stethoscope") {
                    navigationManager.present(.diagnostics)
                }

                drawerButton(title: "Report Issue / Request Features", systemImage: "exclamationmark.bubble") {
                    navigationManager.present(.reportIssues)
                }

                if let url = URL(string: "https://apps.apple.com/us/app/lotus-planner/id6749281062?action=write-review") {
                    Link(destination: url) {
                        drawerLabel(title: "Rate the App", systemImage: "star", isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .help("Rate the App")
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var drawerHeader: some View {
        HStack(spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse Sidebar" : "Expand Sidebar")
        }
        .padding(.horizontal, 11)
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCalendarSelected: Bool {
        navigationManager.currentView == .calendar ||
        navigationManager.currentView == .weeklyView ||
        navigationManager.currentView == .yearlyCalendar ||
        navigationManager.currentView == .timebox
    }

    private func drawerButton(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            drawerLabel(title: title, systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func drawerLabel(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 24, height: 28)

            if isExpanded {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .transition(.opacity)

                Spacer(minLength: 0)
            }
        }
        .foregroundColor(isSelected ? .accentColor : .primary)
        .padding(.horizontal, isExpanded ? 10 : 8)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }
}
