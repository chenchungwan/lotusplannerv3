import SwiftUI

struct SharedNavigationToolbar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var showingAbout = false
    @State private var showingDiagnostics = false
    @State private var showingReportIssues = false
    @State private var showingAITaskEntry = false

    var body: some View {
        HStack(spacing: 8) {
            // Hamburger menu with common actions
            Menu {
                Button("Settings") {
                    navigationManager.showSettings()
                }
                Button("About") {
                    showingAbout = true
                }
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("Diagnostic", systemImage: "stethoscope")
                }
                Button("Report Issue / Request Features") {
                    showingReportIssues = true
                }

                if let url = URL(string: "https://apps.apple.com/us/app/lotus-planner/id6749281062?action=write-review") {
                    Link(destination: url) {
                        Label("Rate the App", systemImage: "star")
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }
            
            // Tasks checklist button (go to Tasks view with current calendar filter)
            Button(action: {
                navigationManager.switchToTasks()
                // Let tasks view sync with current calendar interval instead of forcing "All Tasks"
            }) {
                Image(systemName: "checklist")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(navigationManager.currentView == .tasks && navigationManager.showTasksView ? .accentColor : .secondary)
            }
            
            // Calendar button (always go to Day view)
            Button(action: {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(.day, date: Date())
            }) {
                Image(systemName: "calendar")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(navigationManager.currentView == .calendar || navigationManager.currentView == .tasks && !navigationManager.showTasksView ? .accentColor : .secondary)
            }

            Button {
                showingAITaskEntry = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.accentColor)
            }
            .help("AI Task Entry")
            .disabled(!(auth.isLinked(kind: .personal) || auth.isLinked(kind: .professional)))
            
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
        }
        .sheet(isPresented: $showingReportIssues) {
            ReportIssuesView()
        }
        .sheet(isPresented: $showingAITaskEntry) {
            let personalLinked = auth.isLinked(kind: .personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? .personal : .professional
            AITaskEntryView(
                tasksViewModel: tasksVM,
                authManager: auth,
                appPrefs: appPrefs,
                defaultAccountKind: defaultAccount
            )
        }
    }
}
