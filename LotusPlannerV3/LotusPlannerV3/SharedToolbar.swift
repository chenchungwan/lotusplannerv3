import SwiftUI

struct SharedNavigationToolbar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Settings gear icon
            Button(action: {
                navigationManager.showSettings()
            }) {
                Image(systemName: "gearshape")
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