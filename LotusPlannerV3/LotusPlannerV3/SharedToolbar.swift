import SwiftUI

struct SharedNavigationToolbar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var showingAbout = false
    @State private var showingReportIssues = false
    
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
                Button("Report Issue / Request Features") {
                    showingReportIssues = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }
            
            // Tasks checklist button (always go to Tasks view with All filter)
            Button(action: {
                navigationManager.switchToTasks()
                // Attempt to broadcast desired filter change via NotificationCenter
                NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
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
            
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingReportIssues) {
            ReportIssuesView()
        }
    }
} 