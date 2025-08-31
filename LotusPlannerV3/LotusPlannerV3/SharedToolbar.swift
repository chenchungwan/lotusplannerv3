import SwiftUI

struct SharedNavigationToolbar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Hamburger menu with common actions
            Menu {
                Button("Settings") {
                    navigationManager.showSettings()
                }
                Button("About") {
                    // Placeholder: could present an About sheet
                    NotificationCenter.default.post(name: Notification.Name("LPV3_ShowAbout"), object: nil)
                }
                Button("Report Issue / Request Features") {
                    // Placeholder: could open email or feedback form
                    NotificationCenter.default.post(name: Notification.Name("LPV3_ShowFeedback"), object: nil)
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }
            
            // Tasks checklist button
            Button(action: {
                navigationManager.switchToTasks()
            }) {
                Image(systemName: "checklist")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(navigationManager.currentView == .tasks && navigationManager.showTasksView ? .accentColor : .secondary)
            }
            
            // Calendar button
            Button(action: {
                navigationManager.switchToCalendar()
            }) {
                Image(systemName: "calendar")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .foregroundColor(navigationManager.currentView == .calendar || navigationManager.currentView == .tasks && !navigationManager.showTasksView ? .accentColor : .secondary)
            }
            
        }
    }
} 