import SwiftUI

struct AITaskEntryView: View {
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var authManager: GoogleAuthManager
    @ObservedObject var appPrefs: AppPreferences

    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var proposals: [AITaskActionProposal] = []
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind
    @State private var selectedListId: String = ""
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var errorMessage: String?

    init(
        tasksViewModel: TasksViewModel,
        authManager: GoogleAuthManager,
        appPrefs: AppPreferences,
        defaultAccountKind: GoogleAuthManager.AccountKind
    ) {
        self.tasksViewModel = tasksViewModel
        self.authManager = authManager
        self.appPrefs = appPrefs
        self._selectedAccountKind = State(initialValue: defaultAccountKind)
    }

    private var availableAccounts: [GoogleAuthManager.AccountKind] {
        [.account1, .account2].filter { authManager.isLinked(kind: $0) }
    }

    private var availableLists: [GoogleTaskList] {
        selectedAccountKind == .account1 ? tasksViewModel.account1TaskLists : tasksViewModel.account2TaskLists
    }

    private var selectedProposals: [AITaskActionProposal] {
        proposals.filter(\.isSelected)
    }

    private var canPlan: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private var canApply: Bool {
        !selectedProposals.isEmpty && selectedProposals.allSatisfy(\.canApply) && !isApplying
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ask") {
                    TextEditor(text: $input)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text("Add prep slides for Friday, move Python Day 33 to tomorrow, or move proposal draft to Work")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button {
                        Task { await planActions() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isLoading ? "Thinking" : "Plan Changes")
                        }
                    }
                    .disabled(!canPlan)
                }

                Section("Default Destination") {
                    if availableAccounts.count > 1 {
                        Picker("Account", selection: $selectedAccountKind) {
                            ForEach(availableAccounts, id: \.rawValue) { account in
                                Text(appPrefs.accountName(for: account)).tag(account)
                            }
                        }
                    }

                    Picker("List", selection: $selectedListId) {
                        ForEach(availableLists) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                }

                if !proposals.isEmpty {
                    Section("Preview") {
                        ForEach($proposals) { $proposal in
                            AITaskActionProposalRow(proposal: $proposal)
                        }
                        .onDelete { offsets in
                            proposals.remove(atOffsets: offsets)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("AI Task Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isApplying ? "Applying" : "Apply") {
                        Task { await applySelectedActions() }
                    }
                    .disabled(!canApply)
                }
            }
            .onAppear {
                syncSelectedList()
                Task { await tasksViewModel.loadTasksOnDemand() }
            }
            .onChange(of: selectedAccountKind) { _, _ in
                syncSelectedList()
                resolveProposals()
            }
        }
    }

    private func syncSelectedList() {
        let lists = availableLists
        if !lists.contains(where: { $0.id == selectedListId }) {
            selectedListId = lists.first?.id ?? ""
        }
    }

    private func planActions() async {
        isLoading = true
        errorMessage = nil

        do {
            await tasksViewModel.loadTasksOnDemand()
            let actions = try await ClaudeAIService.shared.planTaskActions(
                from: input,
                taskContext: taskContextForClaude(),
                accountLabels: accountLabelsForClaude()
            )
            await MainActor.run {
                proposals = actions.map { proposal(for: $0) }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func resolveProposals() {
        proposals = proposals.map { proposal in
            var updated = proposal
            updated.resolution = resolve(action: proposal.action)
            return updated
        }
    }

    private func proposal(for action: AITaskAgentAction) -> AITaskActionProposal {
        AITaskActionProposal(action: action, resolution: resolve(action: action))
    }

    private func resolve(action: AITaskAgentAction) -> AITaskActionResolution {
        switch action.type {
        case .createTask:
            guard let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .blocked("Missing task title.")
            }
            guard !selectedListId.isEmpty else {
                return .blocked("Choose a default list.")
            }
            return .create(targetAccount: selectedAccountKind, targetListId: selectedListId, targetListTitle: listTitle(selectedListId, selectedAccountKind))

        case .updateTaskDate:
            guard let match = matchTask(query: action.taskQuery) else {
                return .blocked("Couldn’t find a matching task.")
            }
            guard let dueDate = action.dueDate else {
                return .blocked("Missing target date.")
            }
            return .updateDate(task: match, dueDate: dueDate)

        case .moveTaskToList:
            guard let match = matchTask(query: action.taskQuery) else {
                return .blocked("Couldn’t find a matching task.")
            }
            guard let target = matchList(name: action.targetListName, preferredAccount: action.targetAccountKind, sourceAccount: match.accountKind) else {
                return .blocked("Couldn’t find the target list.")
            }
            return .moveList(task: match, target: target)
        }
    }

    private func applySelectedActions() async {
        guard canApply else { return }
        isApplying = true
        errorMessage = nil

        for proposal in selectedProposals {
            switch proposal.resolution {
            case .create(let targetAccount, let targetListId, _):
                await tasksViewModel.createTask(
                    title: proposal.action.title ?? "",
                    notes: proposal.action.notes,
                    dueDate: proposal.action.dueDate,
                    in: targetListId,
                    for: targetAccount
                )

            case .updateDate(let locatedTask, let dueDate):
                var updatedTask = locatedTask.task
                updatedTask.due = Self.taskDateString(from: dueDate)
                await tasksViewModel.updateTask(updatedTask, in: locatedTask.listId, for: locatedTask.accountKind)

            case .moveList(let locatedTask, let target):
                if locatedTask.accountKind == target.accountKind {
                    _ = await tasksViewModel.moveTask(
                        locatedTask.task,
                        from: locatedTask.listId,
                        to: target.listId,
                        for: locatedTask.accountKind
                    )
                } else {
                    _ = await tasksViewModel.crossAccountMoveTask(
                        locatedTask.task,
                        from: (locatedTask.accountKind, locatedTask.listId),
                        to: (target.accountKind, target.listId)
                    )
                }

            case .blocked:
                break
            }
        }

        await MainActor.run {
            isApplying = false
            dismiss()
        }
    }

    private func accountLabelsForClaude() -> [AIAccountLabel] {
        availableAccounts.map {
            AIAccountLabel(kind: $0, name: appPrefs.accountName(for: $0))
        }
    }

    private func taskContextForClaude() -> String {
        let listsText = allLists().map { list in
            "- \(appPrefs.accountName(for: list.accountKind)) / \(list.listTitle)"
        }.joined(separator: "\n")

        let taskText = allLocatedTasks()
            .filter { !$0.task.isCompleted }
            .prefix(150)
            .map { task in
                let due = task.task.dueDate.map { " due \(Self.displayDateFormatter.string(from: $0))" } ?? ""
                return "- \(task.task.title) [\(appPrefs.accountName(for: task.accountKind)) / \(task.listTitle)]\(due)"
            }
            .joined(separator: "\n")

        return """
        Lists:
        \(listsText.isEmpty ? "No linked task lists loaded." : listsText)

        Existing incomplete tasks:
        \(taskText.isEmpty ? "No tasks loaded." : taskText)
        """
    }

    private func allLocatedTasks() -> [AILocatedTask] {
        var items: [AILocatedTask] = []
        for account in availableAccounts {
            let lists = account == .account1 ? tasksViewModel.account1TaskLists : tasksViewModel.account2TaskLists
            let tasksByList = account == .account1 ? tasksViewModel.account1Tasks : tasksViewModel.account2Tasks
            for list in lists {
                for task in tasksByList[list.id] ?? [] {
                    items.append(AILocatedTask(task: task, listId: list.id, listTitle: list.title, accountKind: account))
                }
            }
        }
        return items
    }

    private func allLists() -> [AIListTarget] {
        availableAccounts.flatMap { account in
            let lists = account == .account1 ? tasksViewModel.account1TaskLists : tasksViewModel.account2TaskLists
            return lists.map { AIListTarget(listId: $0.id, listTitle: $0.title, accountKind: account) }
        }
    }

    private func matchTask(query: String?) -> AILocatedTask? {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalizedQuery = Self.normalized(query)
        let candidates = allLocatedTasks().map { task in
            (task: task, score: Self.matchScore(query: normalizedQuery, candidate: Self.normalized(task.task.title)))
        }
        return candidates
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.task.task.title.count < rhs.task.task.title.count
            }
            .first?
            .task
    }

    private func matchList(
        name: String?,
        preferredAccount: GoogleAuthManager.AccountKind?,
        sourceAccount: GoogleAuthManager.AccountKind
    ) -> AIListTarget? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalizedName = Self.normalized(name)
        let lists = allLists().filter { preferredAccount == nil || $0.accountKind == preferredAccount }
        let candidates = lists.map { list in
            let score = Self.matchScore(query: normalizedName, candidate: Self.normalized(list.listTitle))
            let sameAccountBonus = list.accountKind == sourceAccount ? 5 : 0
            return (list: list, score: score + sameAccountBonus)
        }
        return candidates
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .first?
            .list
    }

    private func listTitle(_ listId: String, _ accountKind: GoogleAuthManager.AccountKind) -> String {
        let lists = accountKind == .account1 ? tasksViewModel.account1TaskLists : tasksViewModel.account2TaskLists
        return lists.first(where: { $0.id == listId })?.title ?? "Selected List"
    }

    private static func matchScore(query: String, candidate: String) -> Int {
        if query == candidate { return 100 }
        if candidate.contains(query) { return 90 }
        if query.contains(candidate) { return 80 }
        let queryWords = Set(query.split(separator: " ").map(String.init))
        let candidateWords = Set(candidate.split(separator: " ").map(String.init))
        let overlap = queryWords.intersection(candidateWords).count
        return overlap == 0 ? 0 : 40 + overlap * 10
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func taskDateString(from date: Date) -> String {
        taskDateFormatter.string(from: date)
    }

    private static let taskDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct AITaskActionProposal: Identifiable {
    let id = UUID()
    var action: AITaskAgentAction
    var resolution: AITaskActionResolution
    var isSelected = true

    var canApply: Bool {
        resolution.canApply
    }
}

private enum AITaskActionResolution {
    case create(targetAccount: GoogleAuthManager.AccountKind, targetListId: String, targetListTitle: String)
    case updateDate(task: AILocatedTask, dueDate: Date)
    case moveList(task: AILocatedTask, target: AIListTarget)
    case blocked(String)

    var canApply: Bool {
        if case .blocked = self { return false }
        return true
    }
}

private struct AILocatedTask: Identifiable, Equatable {
    var id: String { "\(accountKind.rawValue)-\(listId)-\(task.id)" }
    let task: GoogleTask
    let listId: String
    let listTitle: String
    let accountKind: GoogleAuthManager.AccountKind
}

private struct AIListTarget: Identifiable, Equatable {
    var id: String { "\(accountKind.rawValue)-\(listId)" }
    let listId: String
    let listTitle: String
    let accountKind: GoogleAuthManager.AccountKind
}

private struct AITaskActionProposalRow: View {
    @Binding var proposal: AITaskActionProposal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                proposal.isSelected.toggle()
            } label: {
                Image(systemName: proposal.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(proposal.isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!proposal.canApply)

            VStack(alignment: .leading, spacing: 6) {
                Label(actionTitle, systemImage: actionIcon)
                    .font(.body.weight(.medium))

                Text(actionDetail)
                    .font(.footnote)
                    .foregroundColor(proposal.canApply ? .secondary : .red)

                if let notes = proposal.action.notes, proposal.action.type == .createTask {
                    Text(notes)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var actionIcon: String {
        switch proposal.action.type {
        case .createTask: return "plus.circle"
        case .updateTaskDate: return "calendar"
        case .moveTaskToList: return "folder"
        }
    }

    private var actionTitle: String {
        switch proposal.action.type {
        case .createTask:
            return proposal.action.title ?? "Create task"
        case .updateTaskDate:
            return "Reschedule task"
        case .moveTaskToList:
            return "Move task"
        }
    }

    private var actionDetail: String {
        switch proposal.resolution {
        case .create(let targetAccount, _, let targetListTitle):
            let due = proposal.action.dueDate.map { " due \(Self.dateFormatter.string(from: $0))" } ?? ""
            return "Create in \(targetAccount.rawValue) / \(targetListTitle)\(due)"
        case .updateDate(let task, let dueDate):
            return "Move “\(task.task.title)” to \(Self.dateFormatter.string(from: dueDate))"
        case .moveList(let task, let target):
            return "Move “\(task.task.title)” from \(task.listTitle) to \(target.listTitle)"
        case .blocked(let message):
            return message
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
