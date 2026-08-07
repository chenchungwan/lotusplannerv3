import SwiftUI

// MARK: - Create Item Kind

/// The item types the unified create sheet can produce. Declaration order
/// drives the order of the tab strip.
enum CreateItemKind: String, CaseIterable, Identifiable {
    case event
    case task
    case list
    case goal
    case log

    var id: String { rawValue }

    var tabTitle: String {
        switch self {
        case .event: return "Event"
        case .task: return "Task"
        case .list: return "List"
        case .goal: return "Goal"
        case .log: return "Log"
        }
    }

    var tabIcon: String {
        switch self {
        case .event: return "calendar"
        case .task: return "checkmark.circle"
        case .list: return "list.bullet"
        case .goal: return "target"
        case .log: return "heart.text.square"
        }
    }
}

// MARK: - Shared Draft

/// Carries the text the user already typed from one tab to the next, so
/// switching from Task to Event (or any other pair) doesn't throw the work
/// away.
///
/// Deliberately a plain reference type rather than an `ObservableObject`:
/// the forms write to it on every keystroke and re-rendering the whole
/// sheet that often would be wasteful. It is only *read* when a tab
/// switch builds the next form.
final class CreateItemDraft {
    var title: String = ""
    var notes: String = ""
}

// MARK: - Create Item Sheet

/// Single window for creating any item. The tab strip at the top switches
/// which form is shown; each form keeps its own navigation title and
/// Cancel/Create buttons, which surface in this sheet's navigation bar.
struct CreateItemSheet: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var logsVM = LogsViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared

    @State private var kind: CreateItemKind
    @State private var draft = CreateItemDraft()
    @State private var newListName = ""
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?

    init(initialKind: CreateItemKind) {
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CreateItemTabStrip(selection: $kind)
                selectedForm
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var selectedForm: some View {
        switch kind {
        case .event: eventForm
        case .task: taskForm
        case .list: listForm
        case .goal: goalForm
        case .log: logForm
        }
    }

    // MARK: - Forms

    private var eventForm: some View {
        AddItemView(
            currentDate: navigationManager.currentDate,
            tasksViewModel: tasksVM,
            calendarViewModel: calendarVM,
            appPrefs: appPrefs,
            showEventOnly: true,
            isEmbedded: true,
            initialTitle: draft.title,
            initialNotes: draft.notes,
            onDraftChange: updateDraft
        )
    }

    private var taskForm: some View {
        let defaultAccount: GoogleAuthManager.AccountKind = auth.isLinked(kind: .account1) ? .account1 : .account2
        let defaultLists = defaultAccount == .account1 ? tasksVM.account1TaskLists : tasksVM.account2TaskLists
        let defaultListId = defaultLists.first?.id ?? ""
        let newTask = GoogleTask(
            id: UUID().uuidString,
            title: draft.title,
            notes: draft.notes.isEmpty ? nil : draft.notes,
            status: "needsAction",
            due: nil,
            completed: nil,
            updated: nil,
            position: "0"
        )

        return TaskDetailsView(
            task: newTask,
            taskListId: defaultListId,
            accountKind: defaultAccount,
            accentColor: defaultAccount == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
            account1TaskLists: tasksVM.account1TaskLists,
            account2TaskLists: tasksVM.account2TaskLists,
            appPrefs: appPrefs,
            viewModel: tasksVM,
            onSave: { updatedTask in
                Task {
                    await tasksVM.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                }
            },
            onDelete: {},
            onMove: { updatedTask, targetListId in
                Task {
                    await tasksVM.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                }
            },
            onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                Task {
                    await tasksVM.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                }
            },
            isNew: true,
            isEmbedded: true,
            onDraftChange: updateDraft
        )
    }

    private var listForm: some View {
        NewListSheet(
            appPrefs: appPrefs,
            accountKind: newListAccountKind,
            hasAccount1: auth.isLinked(kind: .account1),
            hasAccount2: auth.isLinked(kind: .account2),
            account1Color: appPrefs.account1Color,
            account2Color: appPrefs.account2Color,
            listName: $newListName,
            selectedAccount: $newListAccountKind,
            onCreate: createNewList,
            isEmbedded: true
        )
        .onAppear {
            if newListName.isEmpty {
                newListName = draft.title
            }
        }
        .onChange(of: newListName) { _, newValue in
            draft.title = newValue
        }
    }

    private var goalForm: some View {
        CreateGoalView(
            editingGoal: nil,
            defaultTimeframe: navigationManager.currentInterval,
            defaultDate: navigationManager.currentDate,
            isEmbedded: true,
            initialTitle: draft.title,
            initialNotes: draft.notes,
            onDraftChange: updateDraft
        )
    }

    private var logForm: some View {
        AddLogEntryView(viewModel: logsVM, isEmbedded: true)
    }

    // MARK: - Actions

    private func updateDraft(title: String, notes: String) {
        draft.title = title
        draft.notes = notes
    }

    private func createNewList() {
        guard let accountKind = newListAccountKind else { return }

        Task {
            let title = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
            let _ = await tasksVM.createTaskList(title: title, for: accountKind)
            await MainActor.run {
                navigationManager.dismissActiveSheet()
                newListName = ""
                newListAccountKind = nil
            }
        }
    }
}

// MARK: - Tab Strip

/// Horizontal tab strip shown above the active create form.
private struct CreateItemTabStrip: View {
    @Binding var selection: CreateItemKind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CreateItemKind.allCases) { kind in
                tab(for: kind)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tab(for kind: CreateItemKind) -> some View {
        let isSelected = kind == selection

        return Button {
            guard !isSelected else { return }
            selection = kind
        } label: {
            VStack(spacing: 3) {
                Image(systemName: kind.tabIcon)
                    .font(.system(size: 16, weight: .medium))
                Text(kind.tabTitle)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create \(kind.tabTitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
