import Foundation
import SwiftUI

// MARK: - Navigation Manager

/// Owns the cross-view navigation state: which top-level screen is up,
/// which timeline interval is active, the focused date, and a few
/// transient flags (e.g. settings sheet presentation). Singleton because
/// the navigation surface is global — toolbars on every screen need to
/// drive the same state.
@MainActor
class NavigationManager: ObservableObject {
    static let shared = NavigationManager()

    enum CurrentView {
        case calendar
        case tasks
        case lists
        case goals
        case journal
        case journalDayViews
        case weeklyView
        case gWeekView
        case yearlyCalendar
        case timebox
        case bookView
    }

    @Published var currentView: CurrentView = .calendar
    @Published var showTasksView = false
    @Published var currentInterval: TimelineInterval = .day
    @Published var currentDate: Date = Date()
    @Published var viewRefreshCounter: Int = 0
    @Published var showingSettings = false
    @Published var showingIntegrations = false
    @Published var showingAllTasks = false
    @Published var isShowingTimebox = false

    private init() {}

    func switchToCalendar() {
        // Set the appropriate calendar view based on current interval
        if currentInterval == .year {
            currentView = .yearlyCalendar
        } else {
            currentView = .calendar
        }
        showTasksView = false
        // Trigger data refresh when switching to calendar view
        NotificationCenter.default.post(name: Notification.Name("RefreshCalendarData"), object: nil)
    }

    func switchToTasks() {
        currentView = .tasks
        showTasksView = true
        // Reset showingAllTasks to false so tasks view syncs with current calendar interval
        showingAllTasks = false
    }

    func switchToLists() {
        currentView = .lists
        showTasksView = false
    }

    func switchToGoals() {
        if AppPreferences.shared.hideGoals {
            switchToCalendar()
            return
        }

        currentView = .goals
        showTasksView = false

        if currentInterval == .day {
            currentInterval = .week
        }
    }

    func switchToJournal() {
        currentView = .journal
        showTasksView = false
    }

    func switchToJournalDayViews() {
        currentView = .journalDayViews
        showTasksView = false
        currentInterval = .day // Journal day views are always day view
    }

    func switchToWeeklyView() {
        currentView = .weeklyView
        showTasksView = false
        currentInterval = .week // WeeklyView is always week view
    }

    func switchToYearlyCalendar() {
        currentView = .yearlyCalendar
        showTasksView = false
    }

    func switchToTimebox() {
        currentView = .timebox
        showTasksView = false
        currentInterval = .week
        currentDate = Date()
        viewRefreshCounter += 1
    }

    func switchToBookView() {
        if AppPreferences.shared.hideBookView {
            switchToCalendar()
            return
        }
        currentView = .bookView
        showTasksView = false
    }

    func showSettings() {
        showingSettings = true
    }

    func showIntegrations() {
        showingIntegrations = true
    }

    /// Update the current interval and date from calendar view.
    func updateInterval(_ interval: TimelineInterval, date: Date = Date()) {
        currentInterval = interval
        currentDate = date
    }
}
