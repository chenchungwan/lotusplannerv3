import SwiftUI

struct JournalDayViews: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init() {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
                .background(.ultraThinMaterial)
            
            // Journal View (simplified - no horizontal scroll needed)
            JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .expanded)
                .id(navigationManager.currentDate)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(adaptivePadding)
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    JournalDayViews()
}
