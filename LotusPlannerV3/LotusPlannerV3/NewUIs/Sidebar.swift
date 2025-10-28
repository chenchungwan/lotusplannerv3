import SwiftUI

struct Sidebar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingReportIssues = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Main navigation icons
            VStack(spacing: 12) {
                // Calendar
                Button(action: {
                    navigationManager.switchToCalendar()
                }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(navigationManager.currentView == .calendar ? .accentColor : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(navigationManager.currentView == .calendar ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                }
                
                // Tasks
                Button(action: {
                    navigationManager.switchToTasks()
                }) {
                    Image(systemName: "checklist")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(navigationManager.currentView == .tasks ? .accentColor : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(navigationManager.currentView == .tasks ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                }
                
                // Lists
                Button(action: {
                    navigationManager.switchToLists()
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(navigationManager.currentView == .lists ? .accentColor : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(navigationManager.currentView == .lists ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                }
                
                // Journals
                Button(action: {
                    navigationManager.switchToJournalDayViews()
                }) {
                    Image(systemName: "book")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(navigationManager.currentView == .journalDayViews ? .accentColor : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(navigationManager.currentView == .journalDayViews ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                }
                
                // Goals (if not hidden)
                if !appPrefs.hideGoals {
                    Button(action: {
                        navigationManager.switchToGoals()
                    }) {
                        Image(systemName: "target")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 40, height: 40)
                            .foregroundColor(navigationManager.currentView == .goals ? .accentColor : .secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(navigationManager.currentView == .goals ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                    }
                }
            }
            
            Spacer()
            
            // Settings and utility icons
            VStack(spacing: 12) {
                // Settings
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                
                // About
                Button(action: {
                    showingAbout = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                
                // Report Issues
                Button(action: {
                    showingReportIssues = true
                }) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
            }
        }
        .frame(width: 50)
        .padding(.vertical, 16)
        .padding(.horizontal, 5)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5),
            alignment: .trailing
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingReportIssues) {
            ReportIssuesView()
        }
    }
}

#Preview {
    Sidebar()
}
