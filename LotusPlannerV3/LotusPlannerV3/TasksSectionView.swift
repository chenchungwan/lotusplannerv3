import SwiftUI

// MARK: - Tasks Section View
struct TasksSectionView: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isLinked: Bool
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accountKind: GoogleAuthManager.AccountKind
    let filter: TaskFilter
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    let width: CGFloat
    
    private var isCurrentToolbarPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }

    private var isCurrentPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            contentArea
        }
        .frame(width: width)
        .background(backgroundView)
    }
    
    private var sectionHeader: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(headerColor)
                .font(.title2)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(headerColor)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(headerBackground)
    }
    
    private var headerColor: Color {
        isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : accentColor
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(headerColor.opacity(0.1))
    }
    
    private var contentArea: some View {
        Group {
            if isLinked {
                linkedContent
            } else {
                unlinkedContent
            }
        }
    }
    
    private var linkedContent: some View {
        Group {
            if taskLists.isEmpty {
                loadingView
            } else {
                taskListsGrid
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Loading tasks...")
                .foregroundColor(.secondary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var taskListsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(taskLists) { taskList in
                    taskListCard(for: taskList)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
    
    private func taskListCard(for taskList: GoogleTaskList) -> some View {
        let filteredTasks = tasksDict[taskList.id] ?? []
        return Group {
            if !filteredTasks.isEmpty || filter == .all {
                TaskListCard(
                    taskList: taskList,
                    tasks: filteredTasks,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    filter: filter,
                    onTaskToggle: { task in
                        onTaskToggle(task, taskList.id)
                    },
                    onTaskDetails: { task, listId in
                        onTaskDetails(task, listId)
                    }
                )
            }
        }
    }
    
    private var unlinkedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: unlinkedIcon)
                .font(.system(size: 50))
                .foregroundColor(accentColor.opacity(0.6))
            Text("Link \(title) Account")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(accentColor)
            Text("Connect your \(title.lowercased()) Google account to view and manage your calendar events and tasks")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var unlinkedIcon: String {
        icon.replacingOccurrences(of: ".circle.fill", with: ".badge.plus")
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemBackground))
            .shadow(color: accentColor.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}
