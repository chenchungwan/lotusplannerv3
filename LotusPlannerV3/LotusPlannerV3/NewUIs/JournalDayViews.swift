import SwiftUI

struct JournalDayViews: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager

    init() {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    // Journal Column (only column - removed timeline and tasks)
                    JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .expanded)
                        .id(navigationManager.currentDate)
                        .frame(width: geometry.size.width * 0.95)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(12)
                }
                .frame(width: geometry.size.width)
            }
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            GlobalNavBar()
                .background(.ultraThinMaterial)
        }
    }
}

#Preview {
    JournalDayViews()
}
