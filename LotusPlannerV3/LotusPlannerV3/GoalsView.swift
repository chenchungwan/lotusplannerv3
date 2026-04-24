import SwiftUI

struct GoalsView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var showingCreateGoal = false
    @State private var showingCreateCategory = false
    @State private var goalToEdit: GoalData?
    @State private var selectedGoal: GoalData?
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Computed properties for better performance
    private var sortedCategories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    // Completion statistics for current timeframe
    private var completionStats: (completed: Int, total: Int) {
        let allGoals = goalsManager.goals.filter { goal in
            isGoalInCurrentTimeframe(goal)
        }
        let completed = allGoals.filter { $0.isCompleted }.count
        return (completed, allGoals.count)
    }
    
    // Adaptive column count based on device
    private var adaptiveColumns: [GridItem] {
        let columnCount: Int
        let spacing: CGFloat = adaptiveGridSpacing
        
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            // iPhone portrait: 1 column
            columnCount = 1
        } else if horizontalSizeClass == .compact && verticalSizeClass == .compact {
            // iPhone landscape: 2 columns
            columnCount = 2
        } else {
            // iPad: 2-3 columns depending on width
            columnCount = 2
        }
        
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }
    
    private var adaptiveGridSpacing: CGFloat {
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            return 12 // iPhone portrait: tighter spacing
        } else if horizontalSizeClass == .compact {
            return 12 // iPhone landscape: tighter spacing
        } else {
            return 16 // iPad: standard spacing
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }
    
    private var adaptiveMinCardHeight: CGFloat {
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            return 200 // iPhone portrait: taller cards for readability
        } else if horizontalSizeClass == .compact {
            return 150 // iPhone landscape: shorter cards
        } else {
            return 180 // iPad: medium height
        }
    }
    
    private var filteredGoals: [GoalData] {
        let allGoals = goalsManager.goals
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return allGoals
        case .week:
            return filterGoalsForWeek(allGoals, date: navigationManager.currentDate)
        case .month:
            return filterGoalsForMonth(allGoals, date: navigationManager.currentDate)
        case .year:
            return filterGoalsForYear(allGoals, date: navigationManager.currentDate)
        }
    }
    
    private var goalsTitle: String {
        switch navigationManager.currentInterval {
        case .day:
            return "All Goals"
        case .week:
            let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: navigationManager.currentDate)
            return "Week \(weekNumber) Weekly Goals"
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return "\(formatter.string(from: navigationManager.currentDate)) Monthly Goals"
        case .year:
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year) Yearly Goals"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Summary Section (only for w, m, y views, not day view)
            if navigationManager.currentInterval != .day {
                GoalsSummaryView(
                    completed: completionStats.completed,
                    total: completionStats.total,
                    currentInterval: navigationManager.currentInterval,
                    currentDate: navigationManager.currentDate
                )
            }
            
            // Main Content
            if navigationManager.currentInterval == .day {
                AllGoalsTableContent()
            } else if appPrefs.useGoalCardView {
                // Individual Goal Card Grid View
                GoalCardGridView(
                    sortedCategories: sortedCategories,
                    getFilteredGoals: getFilteredGoalsForCategory,
                    onGoalTap: { goal in
                        selectedGoal = goal
                    },
                    onGoalEdit: { goal in
                        goalToEdit = goal
                    }
                )
            } else {
                // Category Cards Grid View
                ScrollView {
                    LazyVGrid(
                        columns: adaptiveColumns,
                        spacing: adaptiveGridSpacing
                    ) {
                        ForEach(sortedCategories) { category in
                            GoalCategoryCard(
                                category: category,
                                goals: getFilteredGoalsForCategory(category.id),
                                onGoalTap: { goal in
                                    selectedGoal = goal
                                },
                                onGoalEdit: { goal in
                                    goalToEdit = goal
                                },
                                onGoalDelete: { goal in
                                    goalsManager.deleteGoal(goal.id)
                                },
                                onCategoryEdit: { category in
                                    // Handle category edit
                                },
                                onCategoryDelete: { category in
                                    goalsManager.deleteCategory(category.id)
                                },
                                showTags: navigationManager.currentInterval == .day,
                                currentInterval: navigationManager.currentInterval,
                                currentDate: navigationManager.currentDate,
                                showQuickAdd: navigationManager.currentInterval != .day
                            )
                            .frame(minHeight: adaptiveMinCardHeight)
                        }

                        // Add Category Card (only show if under max limit)
                        if goalsManager.canAddCategory {
                            AddCategoryCard(
                                onAddCategory: { categoryName in
                                    goalsManager.addCategory(title: categoryName)
                                }
                            )
                            .frame(minHeight: adaptiveMinCardHeight)
                        }
                    }
                    .padding(adaptivePadding)
                }
            }
        }
        // Use `.sheet(item:)` here instead of the (isPresented:, state:) pair:
        // on Mac Catalyst the two separate state flips race and the sheet
        // builder was running with `selectedGoal == nil`, crashing the app.
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal)
        }
        .sheet(item: $goalToEdit) { goal in
            CreateGoalView(editingGoal: goal) {
                goalToEdit = nil
            }
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalView(
                editingGoal: nil,
                defaultTimeframe: navigationManager.currentInterval,
                defaultDate: navigationManager.currentDate
            ) {
                showingCreateGoal = false
            }
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddGoal"))) { _ in
            showingCreateGoal = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddCategory"))) { _ in
            showingCreateCategory = true
        }
        .onAppear {
            // Set default interval to week for goals view
            if navigationManager.currentInterval == .day {
                navigationManager.currentInterval = .week
            }
            // Only refresh if data is stale
            if goalsManager.categories.isEmpty {
                goalsManager.refreshData()
            }
        }
        .onChange(of: navigationManager.currentDate) { _ in
            // Refresh goals when date changes
            goalsManager.refreshData()
        }
        .onChange(of: navigationManager.currentInterval) { _ in
            // Refresh goals when interval changes
            goalsManager.refreshData()
        }
    }
    
    // MARK: - Filtering Functions
    private func isGoalInCurrentTimeframe(_ goal: GoalData) -> Bool {
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return true
        case .week:
            return isGoalInWeek(goal, date: navigationManager.currentDate)
        case .month:
            return isGoalInMonth(goal, date: navigationManager.currentDate)
        case .year:
            return isGoalInYear(goal, date: navigationManager.currentDate)
        }
    }
    
    private func isGoalInWeek(_ goal: GoalData, date: Date) -> Bool {
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .week && 
               goal.dueDate >= weekInterval.start && 
               goal.dueDate < weekInterval.end
    }
    
    private func isGoalInMonth(_ goal: GoalData, date: Date) -> Bool {
        guard let monthInterval = Calendar.mondayFirst.dateInterval(of: .month, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .month && 
               goal.dueDate >= monthInterval.start && 
               goal.dueDate < monthInterval.end
    }
    
    private func isGoalInYear(_ goal: GoalData, date: Date) -> Bool {
        guard let yearInterval = Calendar.mondayFirst.dateInterval(of: .year, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .year && 
               goal.dueDate >= yearInterval.start && 
               goal.dueDate < yearInterval.end
    }
    
    private func getFilteredGoalsForCategory(_ categoryId: UUID) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return categoryGoals
        case .week:
            return filterGoalsForWeek(categoryGoals, date: navigationManager.currentDate)
        case .month:
            return filterGoalsForMonth(categoryGoals, date: navigationManager.currentDate)
        case .year:
            return filterGoalsForYear(categoryGoals, date: navigationManager.currentDate)
        }
    }
    
    private func filterGoalsForWeek(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: date) else {
            return goals
        }
        return goals.filter { goal in
            goal.targetTimeframe == .week &&
            goal.dueDate >= weekInterval.start &&
            goal.dueDate < weekInterval.end
        }
    }

    private func filterGoalsForMonth(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: date) else {
            return goals
        }
        return goals.filter { goal in
            goal.targetTimeframe == .month &&
            goal.dueDate >= monthInterval.start &&
            goal.dueDate < monthInterval.end
        }
    }

    private func filterGoalsForYear(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let yearInterval = Calendar.current.dateInterval(of: .year, for: date) else {
            return goals
        }
        return goals.filter { goal in
            goal.targetTimeframe == .year &&
            goal.dueDate >= yearInterval.start &&
            goal.dueDate < yearInterval.end
        }
    }
}

// MARK: - Goal Card Grid View (Individual Cards)
struct GoalCardGridView: View {
    let sortedCategories: [GoalCategoryData]
    let getFilteredGoals: (UUID) -> [GoalData]
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void

    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var isCompactDevice: Bool {
        horizontalSizeClass == .compact
    }

    private var columns: [GridItem] {
        if isCompactDevice {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.adaptive(minimum: 298, maximum: 298), spacing: 12)]
        }
    }

    /// All goals ordered by displayOrder, falling back to category position
    private var orderedGoals: [(goal: GoalData, category: GoalCategoryData)] {
        var result: [(GoalData, GoalCategoryData)] = []
        for category in sortedCategories {
            let goals = getFilteredGoals(category.id)
            for goal in goals {
                result.append((goal, category))
            }
        }
        return result.sorted(by: { (a: (goal: GoalData, category: GoalCategoryData), b: (goal: GoalData, category: GoalCategoryData)) in
            a.goal.displayOrder < b.goal.displayOrder
        })
    }

    var body: some View {
        ScrollView {
            if orderedGoals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No goals for this period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(orderedGoals, id: \.goal.id) { item in
                        // Resolve tasks at THIS level where @ObservedObject tasksVM triggers re-render
                        let tasks = item.goal.linkedTasks.compactMap { linked -> GoalCardTaskInfo? in
                            for (_, tasks) in tasksVM.personalTasks {
                                if let t = tasks.first(where: { $0.id == linked.taskId }) {
                                    return GoalCardTaskInfo(id: t.id, title: t.title, isCompleted: t.isCompleted, dueDate: t.dueDate)
                                }
                            }
                            for (_, tasks) in tasksVM.professionalTasks {
                                if let t = tasks.first(where: { $0.id == linked.taskId }) {
                                    return GoalCardTaskInfo(id: t.id, title: t.title, isCompleted: t.isCompleted, dueDate: t.dueDate)
                                }
                            }
                            return GoalCardTaskInfo(id: linked.taskId, title: linked.taskTitle ?? "Task", isCompleted: false, dueDate: nil)
                        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

                        GoalCard(
                            goal: item.goal,
                            category: item.category,
                            onTap: { onGoalTap(item.goal) },
                            onEdit: { onGoalEdit(item.goal) },
                            taskInfos: tasks
                        )
                        .draggable(item.goal.id.uuidString)
                        .dropDestination(for: String.self) { droppedItems, _ in
                            guard let droppedId = droppedItems.first,
                                  let droppedUUID = UUID(uuidString: droppedId),
                                  droppedUUID != item.goal.id else { return false }
                            reorderGoal(droppedUUID, before: item.goal.id)
                            return true
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func reorderGoal(_ draggedId: UUID, before targetId: UUID) {
        var ids = orderedGoals.map { $0.goal.id }
        guard let fromIndex = ids.firstIndex(of: draggedId),
              let toIndex = ids.firstIndex(of: targetId) else { return }
        ids.remove(at: fromIndex)
        ids.insert(draggedId, at: toIndex)
        goalsManager.updateGoalDisplayOrders(ids)
    }
}

// MARK: - Task Info for Goal Card
struct GoalCardTaskInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
}

// MARK: - Individual Goal Card
struct GoalCard: View {
    let goal: GoalData
    let category: GoalCategoryData
    let onTap: () -> Void
    let onEdit: () -> Void
    var taskInfos: [GoalCardTaskInfo] = []

    @ObservedObject private var goalsManager = GoalsManager.shared

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private var isOverdue: Bool {
        goal.daysRemaining <= 0 && !goal.isCompleted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Goal title with checkbox
            HStack(alignment: .top, spacing: 8) {
                Button {
                    goalsManager.toggleGoalCompletion(goal.id)
                } label: {
                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(goal.isCompleted ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())

                Text(goal.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .strikethrough(goal.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            // Category tag on its own line
            Text(category.title)
                .font(.caption2)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .fixedSize()

            // Tasks from pre-resolved taskInfos
            if !taskInfos.isEmpty {
                VStack(spacing: 6) {
                    ForEach(taskInfos) { info in
                        HStack(spacing: 8) {
                            Image(systemName: info.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(info.isCompleted ? .green : .secondary)
                                .font(.body)
                            Text(info.title)
                                .font(.subheadline)
                                .strikethrough(info.isCompleted)
                                .foregroundColor(info.isCompleted ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if let dueDate = info.dueDate {
                                let tag = dueDateTagInfo(dueDate, isCompleted: info.isCompleted)
                                Text(tag.text)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(tag.bgColor)
                                    .foregroundColor(tag.textColor)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray6).opacity(0.7))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private func dueDateTagInfo(_ date: Date, isCompleted: Bool) -> (text: String, textColor: Color, bgColor: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)

        if isCompleted {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        } else if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, .accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        }
    }
}

// MARK: - Goal Category Card
struct GoalCategoryCard: View {
    let category: GoalCategoryData
    let goals: [GoalData]
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void
    let onGoalDelete: (GoalData) -> Void
    let onCategoryEdit: (GoalCategoryData) -> Void
    let onCategoryDelete: (GoalCategoryData) -> Void
    let showTags: Bool
    let currentInterval: TimelineInterval
    let currentDate: Date
    let showQuickAdd: Bool
    
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingCopyAlert = false
    @State private var showingNoGoalsAlert = false
    @State private var isAddingQuickGoal = false
    @State private var newGoalTitle = ""
    @FocusState private var isQuickGoalFieldFocused: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 12
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 6 : 8
    }
    
    // Computed properties for better performance
    private var completedGoalsCount: Int {
        goals.filter { $0.isCompleted }.count
    }
    
    private var totalGoalsCount: Int {
        goals.count
    }
    
    // Check if we should show the repeat icon
    private var shouldShowRepeatIcon: Bool {
        // Only show in week, month, year views (not day view which is "All Goals")
        // Always show the icon to allow repeated copying from previous period
        return currentInterval != .day
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: adaptiveSpacing) {
            // Header with title
            HStack {
                if isEditingTitle {
                    TextField("Category name", text: $editedTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveCategoryTitle()
                        }
                } else {
                    Text("\(category.title) (\(totalGoalsCount))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .onTapGesture {
                            startEditingTitle()
                        }
                }
                
                Spacer()
                
                if isEditingTitle {
                    Button("Save") {
                        saveCategoryTitle()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                // Repeat icon to copy goals from previous period
                if shouldShowRepeatIcon {
                    Button(action: {
                        showingCopyAlert = true
                    }) {
                        Image(systemName: "repeat")
                            .font(.body) // Larger for better tap target
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, adaptivePadding)
            .padding(.top, adaptivePadding)
            
            Divider()
            
            // Goals list
            ScrollView {
                LazyVStack(spacing: adaptiveSpacing) {
                    ForEach(goals) { goal in
                        GoalRow(
                            goal: goal,
                            onTap: { 
                                goalsManager.toggleGoalCompletion(goal.id)
                            },
                            onEdit: { onGoalEdit(goal) },
                            onDelete: { onGoalDelete(goal) },
                            showTags: showTags
                        )
                    }
                    
                    if goals.isEmpty {
                        Text("No goals yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                    
                    if showQuickAdd {
                        quickAddGoalRow
                    }
                }
                .padding(.horizontal, adaptivePadding / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .onChange(of: showQuickAdd) { value in
            if !value {
                cancelQuickGoalInline()
            }
        }
        .alert("Copy Goals from Previous Period?", isPresented: $showingCopyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Copy", role: .none) {
                copyGoalsFromPreviousPeriod()
            }
        } message: {
            Text("This will copy all \(currentInterval.rawValue.lowercased()) goals from the previous \(currentInterval.rawValue.lowercased()) to this period. Your existing goals will be kept. Are you sure?")
        }
        .alert("No Goals to Copy", isPresented: $showingNoGoalsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There are no \(currentInterval.rawValue.lowercased()) goals in the previous period to copy.")
        }
    }
    
    @ViewBuilder
    private var quickAddGoalRow: some View {
        if isAddingQuickGoal {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                TextField("New goal", text: $newGoalTitle)
                    .font(.body)
                    .focused($isQuickGoalFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        createQuickGoalInline()
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isQuickGoalFieldFocused = true
                        }
                    }
                
                Button {
                    cancelQuickGoalInline()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel quick goal")
            }
            .padding(adaptivePadding)
        } else {
            Button {
                isAddingQuickGoal = true
                newGoalTitle = ""
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Text("New goal")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(adaptivePadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add quick goal")
        }
    }
    
    private func cancelQuickGoalInline() {
        isAddingQuickGoal = false
        newGoalTitle = ""
        isQuickGoalFieldFocused = false
    }
    
    private func createQuickGoalInline() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelQuickGoalInline()
            return
        }
        
        let timeframe = convertToGoalTimeframe(currentInterval)
        let dueDate = quickGoalDueDate(for: timeframe)
        
        let newGoal = GoalData(
            title: trimmed,
            description: "",
            successMetric: "",
            categoryId: category.id,
            targetTimeframe: timeframe,
            dueDate: dueDate,
            isCompleted: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        goalsManager.addGoal(newGoal)
        cancelQuickGoalInline()
    }
    
    private func quickGoalDueDate(for timeframe: GoalTimeframe) -> Date {
        switch timeframe {
        case .week:
            return GoalData.calculateDueDate(for: .week, from: currentDate)
        case .month:
            return GoalData.calculateDueDate(for: .month, from: currentDate)
        case .year:
            return GoalData.calculateDueDate(for: .year, from: currentDate)
        }
    }
    
    private func startEditingTitle() {
        editedTitle = category.title
        isEditingTitle = true
    }
    
    private func saveCategoryTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var updatedCategory = category
            updatedCategory.title = trimmed
            updatedCategory.updatedAt = Date()
            onCategoryEdit(updatedCategory)
        }
        isEditingTitle = false
    }
    
    private func copyGoalsFromPreviousPeriod() {
        let calendar = Calendar.mondayFirst
        
        // Calculate previous period based on current interval
        let previousPeriodStart: Date
        let previousPeriodEnd: Date
        
        switch currentInterval {
        case .week:
            // Get previous week
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate),
                  let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
                  let prevWeekInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekStart) else {
                return
            }
            previousPeriodStart = prevWeekInterval.start
            previousPeriodEnd = prevWeekInterval.end
            
        case .month:
            // Get previous month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
                  let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthInterval.start),
                  let prevMonthInterval = calendar.dateInterval(of: .month, for: prevMonthStart) else {
                return
            }
            previousPeriodStart = prevMonthInterval.start
            previousPeriodEnd = prevMonthInterval.end
            
        case .year:
            // Get previous year
            guard let yearInterval = calendar.dateInterval(of: .year, for: currentDate),
                  let prevYearStart = calendar.date(byAdding: .year, value: -1, to: yearInterval.start),
                  let prevYearInterval = calendar.dateInterval(of: .year, for: prevYearStart) else {
                return
            }
            previousPeriodStart = prevYearInterval.start
            previousPeriodEnd = prevYearInterval.end
            
        case .day:
            return // Should not happen due to shouldShowRepeatIcon check
        }
        
        // Get all goals from previous period for this category with matching timeframe type
        let previousPeriodGoals = goalsManager.goals.filter { goal in
            goal.categoryId == category.id &&
            goal.targetTimeframe == convertToGoalTimeframe(currentInterval) &&
            goal.dueDate >= previousPeriodStart &&
            goal.dueDate < previousPeriodEnd
        }
        
        // Check if there are any goals to copy
        if previousPeriodGoals.isEmpty {
            // Show alert that no goals were found
            showingNoGoalsAlert = true
            return
        }
        
        // Calculate the new due date (shift by one period forward)
        let periodShift: DateComponents
        switch currentInterval {
        case .week:
            periodShift = DateComponents(weekOfYear: 1)
        case .month:
            periodShift = DateComponents(month: 1)
        case .year:
            periodShift = DateComponents(year: 1)
        case .day:
            return
        }
        
        // Copy each goal to the current period
        for oldGoal in previousPeriodGoals {
            guard let newDueDate = calendar.date(byAdding: periodShift, to: oldGoal.dueDate) else {
                continue
            }
            
            // Create new goal with same properties but new due date and not completed
            let newGoal = GoalData(
                id: UUID(),
                title: oldGoal.title,
                description: oldGoal.description,
                successMetric: oldGoal.successMetric,
                categoryId: oldGoal.categoryId,
                targetTimeframe: oldGoal.targetTimeframe,
                dueDate: newDueDate,
                isCompleted: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            goalsManager.addGoal(newGoal)
        }
        
        // Post notification to refresh All Goals view
        NotificationCenter.default.post(name: Notification.Name("RefreshAllGoalsView"), object: nil)
    }
    
    private func convertToGoalTimeframe(_ interval: TimelineInterval) -> GoalTimeframe {
        switch interval {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        case .day:
            return .week // Fallback, shouldn't happen
        }
    }
}

// MARK: - Goal Row
struct GoalRow: View {
    let goal: GoalData
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let showTags: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared

    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 8
    }

    private var adaptiveVerticalPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 4
    }

    // Computed properties for better performance
    private var isOverdue: Bool {
        goal.dueDate < Date() && !goal.isCompleted
    }

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: goal.dueDate)
        let components = calendar.dateComponents([.day], from: today, to: dueDate)
        return components.day ?? 0
    }

    private func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // Helper to get task from linked task data — searches all lists
    private func getTask(from linkedTask: LinkedTaskData) -> GoogleTask? {
        // First try the stored list
        let tasksDict = linkedTask.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        if let task = tasksDict[linkedTask.listId]?.first(where: { $0.id == linkedTask.taskId }) {
            return task
        }
        // Search all lists in case the task was moved
        for (_, tasks) in tasksVM.personalTasks {
            if let task = tasks.first(where: { $0.id == linkedTask.taskId }) { return task }
        }
        for (_, tasks) in tasksVM.professionalTasks {
            if let task = tasks.first(where: { $0.id == linkedTask.taskId }) { return task }
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox (larger tap target) - aligned to top
            Button(action: onTap) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3) // Slightly larger for better tap target
                    .foregroundColor(goal.isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())

            // Goal content
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.body)
                    .strikethrough(goal.isCompleted)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                if showTags {
                    HStack(spacing: 4) {
                        Text(goal.targetTimeframe.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Text(formatDueDate(goal.dueDate))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isOverdue ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(isOverdue ? .red : .green)
                            .cornerRadius(4)

                        Spacer()
                    }
                }

                // Linked tasks section
                if !goal.linkedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(goal.linkedTasks, id: \.taskId) { linkedTask in
                            let task = getTask(from: linkedTask)
                            HStack(spacing: 6) {
                                Image(systemName: task?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundColor(task?.isCompleted == true ? .green : .secondary)
                                Text(task?.title ?? linkedTask.taskTitle ?? "Task")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .strikethrough(task?.isCompleted == true)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit()
            }

            Spacer()
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, adaptiveVerticalPadding)
    }
}

// MARK: - Add Category Card
struct AddCategoryCard: View {
    let onAddCategory: (String) -> Void
    
    @State private var isAdding = false
    @State private var newCategoryTitle = ""
    
    var body: some View {
        VStack(spacing: 12) {
            if isAdding {
                VStack(spacing: 16) {
                    Text("New Category")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    TextField("Category name", text: $newCategoryTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addCategory()
                        }
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            cancelAdding()
                        }
                        .foregroundColor(.secondary)
                        
                        Button("Add") {
                            addCategory()
                        }
                        .foregroundColor(.blue)
                        .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            } else {
                Button(action: {
                    isAdding = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Add Category")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
        )
    }
    
    private func addCategory() {
        let trimmed = newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onAddCategory(trimmed)
            cancelAdding()
        }
    }
    
    private func cancelAdding() {
        isAdding = false
        newCategoryTitle = ""
    }
}

// MARK: - Create Goal View (3-Step Flow)
struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    let editingGoal: GoalData?
    let onDismiss: () -> Void
    let defaultTimeframe: TimelineInterval?
    let defaultDate: Date?

    @State private var title = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedTimeframe: GoalTimeframe = .year
    @State private var selectedDate = Date()
    @State private var notes = ""

    @State private var taskItems: [PendingTask] = []
    @State private var selectedGoalAccountKind: GoogleAuthManager.AccountKind = .personal
    @State private var selectedGoalListId: String = ""

    // Editing
    @State private var showingDeleteAlert = false
    @State private var showingTaskPicker = false
    @State private var selectedTaskForDetail: TaskDetailSelection?
    @State private var showingUnlinkTaskAlert = false
    @State private var pendingUnlinkTask: PendingTask?

    struct TaskDetailSelection: Identifiable {
        let id: String
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }

    struct PendingTask: Identifiable {
        let id = UUID()
        var title: String
        var dueDate: Date
        var accountKind: GoogleAuthManager.AccountKind = .personal
        var listId: String = ""
        var existingTaskId: String? = nil // Non-nil if this is an already-created task
    }

    init(editingGoal: GoalData? = nil, defaultTimeframe: TimelineInterval? = nil, defaultDate: Date? = nil, onDismiss: @escaping () -> Void = {}) {
        self.editingGoal = editingGoal
        self.onDismiss = onDismiss
        self.defaultTimeframe = defaultTimeframe
        self.defaultDate = defaultDate
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategoryId != nil
    }

    private var availableTaskLists: [(list: GoogleTaskList, kind: GoogleAuthManager.AccountKind)] {
        var result: [(GoogleTaskList, GoogleAuthManager.AccountKind)] = []
        for list in tasksVM.personalTaskLists {
            result.append((list, .personal))
        }
        for list in tasksVM.professionalTaskLists {
            result.append((list, .professional))
        }
        return result
    }

    private var defaultListId: String {
        tasksVM.personalTaskLists.first?.id ?? tasksVM.professionalTaskLists.first?.id ?? ""
    }

    private var defaultAccountKind: GoogleAuthManager.AccountKind {
        if !tasksVM.personalTaskLists.isEmpty { return .personal }
        return .professional
    }

    @ViewBuilder
    private var formContent: some View {
        // Goal Details
        goalDetailsSection

        // Tasks
        tasksSection

        // Notes
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("Optional notes...", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }

        // Delete
        if editingGoal != nil {
            Button(action: { showingDeleteAlert = true }) {
                HStack {
                    Spacer()
                    Text("Delete Goal")
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            .padding(.top, 8)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                #if targetEnvironment(macCatalyst)
                // Form is bridged to NSStackView under Mac Catalyst's Mac idiom
                // and produces stable, deterministic layout. ScrollView+VStack
                // with the nested HStacks/Menus in this view triggers an Auto
                // Layout cycle that locks the main thread (CreateCategoryView,
                // which uses Form, doesn't exhibit the freeze; this view did).
                Form {
                    formContent
                }
                #else
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        formContent
                    }
                    .padding()
                }
                #endif
            }
            .navigationTitle(editingGoal != nil ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveGoal()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(editingGoal != nil ? "Save" : "Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .confirmationDialog("Delete Goal", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
                let taskCount = taskItems.filter { $0.existingTaskId != nil }.count
                if taskCount > 0 {
                    Button("Delete Goal & \(taskCount) Task\(taskCount == 1 ? "" : "s")", role: .destructive) {
                        deleteGoalWithTasks()
                    }
                    Button("Delete Goal Only (keep tasks)") {
                        deleteGoalOnly()
                    }
                } else {
                    Button("Delete Goal", role: .destructive) {
                        deleteGoalOnly()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let taskCount = taskItems.filter { $0.existingTaskId != nil }.count
                if taskCount > 0 {
                    Text("Do you also want to delete the \(taskCount) linked task\(taskCount == 1 ? "" : "s") from Google Tasks?")
                } else {
                    Text("Are you sure you want to delete '\(title)'?")
                }
            }
            .confirmationDialog("Remove Task", isPresented: $showingUnlinkTaskAlert, titleVisibility: .visible) {
                Button("Unlink Only (keep task)") {
                    if let task = pendingUnlinkTask {
                        taskItems.removeAll { $0.id == task.id }
                    }
                    pendingUnlinkTask = nil
                }
                Button("Unlink & Delete Task", role: .destructive) {
                    if let task = pendingUnlinkTask {
                        // Delete from Google Tasks
                        if let result = lookupTask(task) {
                            Task {
                                await tasksVM.deleteTask(result.task, from: result.listId, for: result.kind)
                            }
                        }
                        taskItems.removeAll { $0.id == task.id }
                    }
                    pendingUnlinkTask = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnlinkTask = nil
                }
            } message: {
                Text("Do you want to also delete this task from Google Tasks, or just remove it from this goal?")
            }
        }
        .onAppear { populateForm() }
    }

    // MARK: - Goal Details Section

    private var goalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. Run a 5K race by September", text: $title, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Category", selection: Binding(
                    get: { selectedCategoryId },
                    set: { selectedCategoryId = $0 }
                )) {
                    Text("Select a category").tag(nil as UUID?)
                    ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }), id: \.id) { category in
                        Text(category.title).tag(category.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([GoalTimeframe.year, GoalTimeframe.month, GoalTimeframe.week], id: \.self) { timeframe in
                            Button {
                                selectedTimeframe = timeframe
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedTimeframe == timeframe ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedTimeframe == timeframe ? .accentColor : .secondary)
                                    Text(timeframe.displayName)
                                        .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        #if targetEnvironment(macCatalyst)
                        // The custom Year/Month/Week picker views use `.menu` style
                        // on Catalyst (wheel pickers crash under the Mac idiom),
                        // and stacking several `NSPopUpButton`-backed pickers inside
                        // the ScrollView triggers a layout feedback loop that locks
                        // the main thread. The native compact DatePicker is bridged
                        // to a lightweight popover and avoids that path entirely;
                        // calculateDueDate() still snaps to the selected timeframe.
                        DatePicker(
                            "Due Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.calendar, Calendar.mondayFirst)
                        #else
                        Group {
                            switch selectedTimeframe {
                            case .year: YearPickerView(selectedDate: $selectedDate)
                            case .month: MonthPickerView(selectedDate: $selectedDate)
                            case .week: WeekPickerView(selectedDate: $selectedDate)
                            }
                        }
                        .frame(height: 100)
                        .clipped()
                        #endif

                        Text("Due: \(calculateDueDate().formatted(date: .abbreviated, time: .omitted))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            // Default Task List
            VStack(alignment: .leading, spacing: 8) {
                Text("Task List")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("New tasks for this goal will be created in this list")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach([GoogleAuthManager.AccountKind.personal, .professional], id: \.self) { kind in
                        if authManager.isLinked(kind: kind) {
                            let lists = kind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
                            if !lists.isEmpty {
                                Menu {
                                    ForEach(lists) { list in
                                        Button {
                                            selectedGoalAccountKind = kind
                                            selectedGoalListId = list.id
                                        } label: {
                                            HStack {
                                                Text(list.title)
                                                if selectedGoalAccountKind == kind && selectedGoalListId == list.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    let currentList = lists.first(where: { $0.id == selectedGoalListId && selectedGoalAccountKind == kind })
                                    HStack(spacing: 4) {
                                        Image(systemName: selectedGoalAccountKind == kind ? "largecircle.fill.circle" : "circle")
                                            .font(.caption)
                                            .foregroundColor(selectedGoalAccountKind == kind ? (kind == .personal ? appPrefs.personalColor : appPrefs.professionalColor) : .secondary)
                                        Text(appPrefs.accountName(for: kind))
                                            .font(.subheadline)
                                        if let currentList, selectedGoalAccountKind == kind {
                                            Text("/ \(currentList.title)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.subheadline)
                .fontWeight(.semibold)

            let sortedIndices = taskItems.indices.sorted { a, b in
                let aDate = resolvedDueDate(taskItems[a])
                let bDate = resolvedDueDate(taskItems[b])
                return aDate < bDate
            }
            ForEach(sortedIndices, id: \.self) { index in
                if taskItems[index].existingTaskId != nil {
                    existingTaskRow(taskItems[index])
                } else {
                    newTaskRow($taskItems[index])
                }
            }

            HStack(spacing: 16) {
                Button {
                    addTaskItem()
                } label: {
                    Label("New Task", systemImage: "plus.circle.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    showingTaskPicker = true
                } label: {
                    Label("Link Existing", systemImage: "link.circle.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingTaskPicker) {
            TaskPickerSheet(
                tasksVM: tasksVM,
                alreadyLinkedIds: Set(taskItems.compactMap { $0.existingTaskId }),
                onSelect: { task, listId, kind in
                    var dueDate = Date()
                    if let dueDateStr = task.due {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        if let parsed = formatter.date(from: dueDateStr) { dueDate = parsed }
                    }
                    taskItems.append(PendingTask(
                        title: task.title,
                        dueDate: dueDate,
                        accountKind: kind,
                        listId: listId,
                        existingTaskId: task.id
                    ))
                }
            )
        }
        .sheet(item: $selectedTaskForDetail, onDismiss: {
            // Refresh taskItems from goal's current linkedTasks after task detail changes
            if let goal = editingGoal, let currentGoal = goalsManager.goals.first(where: { $0.id == goal.id }) {
                refreshTaskItems(from: currentGoal)
            }
        }) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksVM,
                onSave: { updatedTask in
                    Task {
                        await tasksVM.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        await tasksVM.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        // Remove from local taskItems
                        taskItems.removeAll { $0.existingTaskId == sel.task.id }
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksVM.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksVM.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }

    // MARK: - Task Row Helpers

    private func existingTaskRow(_ item: PendingTask) -> some View {
        let result = lookupTask(item)
        let task = result?.task
        let isCompleted = task?.isCompleted ?? false
        let listName = listNameForTask(item)

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .secondary)
                .font(.body)

            Text(task?.title ?? item.title)
                .font(.body)
                .strikethrough(isCompleted)
                .foregroundColor(isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if !listName.isEmpty {
                Text(listName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            let tag = dueDateTagStyle(task?.dueDate ?? item.dueDate, isCompleted: isCompleted)
            Text(tag.text)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tag.bgColor)
                .foregroundColor(tag.textColor)
                .cornerRadius(4)

            Button {
                pendingUnlinkTask = item
                showingUnlinkTaskAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let result = lookupTask(item) {
                selectedTaskForDetail = TaskDetailSelection(
                    id: result.task.id,
                    task: result.task,
                    listId: result.listId,
                    accountKind: result.kind
                )
            }
        }
    }

    private func newTaskRow(_ item: Binding<PendingTask>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.body)
                TextField("Task name", text: item.title)
                    .textFieldStyle(.roundedBorder)
                Button {
                    taskItems.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                DatePicker("Due", selection: item.dueDate, in: ...calculateDueDate(), displayedComponents: .date)
                    .environment(\.calendar, Calendar.mondayFirst)
                    .font(.caption)

                if availableTaskLists.count > 1 {
                    Picker("List", selection: Binding(
                        get: { "\(item.wrappedValue.accountKind == .personal ? "p" : "w"):\(item.wrappedValue.listId)" },
                        set: { newValue in
                            let parts = newValue.split(separator: ":")
                            if parts.count == 2 {
                                item.wrappedValue.accountKind = parts[0] == "p" ? .personal : .professional
                                item.wrappedValue.listId = String(parts[1])
                            }
                        }
                    )) {
                        ForEach(availableTaskLists, id: \.list.id) { entry in
                            let prefix = entry.kind == .personal ? "Personal" : "Work"
                            Text("\(prefix): \(entry.list.title)")
                                .tag("\(entry.kind == .personal ? "p" : "w"):\(entry.list.id)")
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func lookupTask(_ item: PendingTask) -> (task: GoogleTask, listId: String, kind: GoogleAuthManager.AccountKind)? {
        guard let taskId = item.existingTaskId else { return nil }
        // First try stored list
        let tasksDict = item.accountKind == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        if let task = tasksDict[item.listId]?.first(where: { $0.id == taskId }) {
            return (task, item.listId, item.accountKind)
        }
        // Search all lists in case the task was moved
        for (listId, tasks) in tasksVM.personalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return (task, listId, .personal) }
        }
        for (listId, tasks) in tasksVM.professionalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return (task, listId, .professional) }
        }
        return nil
    }

    private func listNameForTask(_ item: PendingTask) -> String {
        // Use actual list from lookup, not stored list ID
        if let result = lookupTask(item) {
            let lists = result.kind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            return lists.first(where: { $0.id == result.listId })?.title ?? ""
        }
        let lists = item.accountKind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        return lists.first(where: { $0.id == item.listId })?.title ?? ""
    }

    // MARK: - Helpers

    private func addTaskItem() {
        let dueDate = calculateDueDate()
        taskItems.append(PendingTask(
            title: "",
            dueDate: dueDate,
            accountKind: selectedGoalAccountKind,
            listId: selectedGoalListId
        ))
    }

    private func calculateDueDate() -> Date {
        let calendar = Calendar.mondayFirst
        switch selectedTimeframe {
        case .week:
            // End of Monday-first week = Sunday
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) {
                return calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? selectedDate
            }
            return selectedDate
        case .month:
            if let end = calendar.dateInterval(of: .month, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
            }
            return selectedDate
        case .year:
            if let end = calendar.dateInterval(of: .year, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
            }
            return selectedDate
        }
    }

    private func populateForm() {
        // Use fresh goal data from GoalsManager (not stale copy passed in)
        let goal: GoalData? = editingGoal.flatMap { eg in
            goalsManager.goals.first(where: { $0.id == eg.id })
        } ?? editingGoal

        // Set default task list
        selectedGoalAccountKind = defaultAccountKind
        selectedGoalListId = defaultListId

        if let goal {
            title = goal.title
            selectedCategoryId = goal.categoryId
            selectedTimeframe = goal.targetTimeframe
            selectedDate = goal.dueDate
            notes = goal.extendedData?.notes ?? ""

            // Restore saved default list, or fall back to first linked task's list
            if let savedListId = goal.extendedData?.defaultListId, !savedListId.isEmpty {
                selectedGoalListId = savedListId
                if goal.extendedData?.defaultAccountKind == "professional" {
                    selectedGoalAccountKind = .professional
                } else {
                    selectedGoalAccountKind = .personal
                }
            } else if let firstLinked = goal.linkedTasks.first {
                selectedGoalAccountKind = firstLinked.accountKindEnum
                selectedGoalListId = firstLinked.listId
            }

            // Populate linked tasks as PendingTask items for editing
            for linked in goal.linkedTasks {
                // Search all lists to find the task (may have been moved)
                var foundTask: GoogleTask? = nil
                var foundListId = linked.listId
                var foundKind = linked.accountKindEnum

                // Try stored list first
                let tasksDict = linked.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
                if let task = tasksDict[linked.listId]?.first(where: { $0.id == linked.taskId }) {
                    foundTask = task
                } else {
                    // Search all lists
                    for (listId, tasks) in tasksVM.personalTasks {
                        if let task = tasks.first(where: { $0.id == linked.taskId }) {
                            foundTask = task; foundListId = listId; foundKind = .personal; break
                        }
                    }
                    if foundTask == nil {
                        for (listId, tasks) in tasksVM.professionalTasks {
                            if let task = tasks.first(where: { $0.id == linked.taskId }) {
                                foundTask = task; foundListId = listId; foundKind = .professional; break
                            }
                        }
                    }
                }

                var dueDate = Date()
                if let dueDateStr = foundTask?.due {
                    // Try full format first, then date-only
                    let fullFormatter = DateFormatter()
                    fullFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                    fullFormatter.locale = Locale(identifier: "en_US_POSIX")
                    let shortFormatter = DateFormatter()
                    shortFormatter.dateFormat = "yyyy-MM-dd"
                    shortFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dueDate = fullFormatter.date(from: dueDateStr)
                        ?? shortFormatter.date(from: String(dueDateStr.prefix(10)))
                        ?? Date()
                } else if let taskDueDate = foundTask?.dueDate {
                    dueDate = taskDueDate
                }

                taskItems.append(PendingTask(
                    title: foundTask?.title ?? linked.taskTitle ?? "Task",
                    dueDate: dueDate,
                    accountKind: foundKind,
                    listId: foundListId,
                    existingTaskId: linked.taskId
                ))
            }
        } else {
            selectedCategoryId = goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }).first?.id

            if let defaultInterval = defaultTimeframe, let date = defaultDate {
                let calendar = Calendar.mondayFirst
                switch defaultInterval {
                case .day, .week:
                    selectedTimeframe = .week
                    if let i = calendar.dateInterval(of: .weekOfYear, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .month:
                    selectedTimeframe = .month
                    if let i = calendar.dateInterval(of: .month, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .year:
                    selectedTimeframe = .year
                    if let i = calendar.dateInterval(of: .year, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                }
            } else {
                selectedTimeframe = .year
                selectedDate = Date()
            }
        }
    }

    private func refreshTaskItems(from goal: GoalData) {
        // Keep any new (unsaved) tasks, rebuild existing task items from goal's current links
        let newTasks = taskItems.filter { $0.existingTaskId == nil }
        var existingTasks: [PendingTask] = []

        for linked in goal.linkedTasks {
            var foundTask: GoogleTask? = nil
            var foundListId = linked.listId
            var foundKind = linked.accountKindEnum

            // Search all lists to find the task
            for (listId, tasks) in tasksVM.personalTasks {
                if let task = tasks.first(where: { $0.id == linked.taskId }) {
                    foundTask = task; foundListId = listId; foundKind = .personal; break
                }
            }
            if foundTask == nil {
                for (listId, tasks) in tasksVM.professionalTasks {
                    if let task = tasks.first(where: { $0.id == linked.taskId }) {
                        foundTask = task; foundListId = listId; foundKind = .professional; break
                    }
                }
            }

            let dueDate = foundTask?.dueDate ?? Date()
            existingTasks.append(PendingTask(
                title: foundTask?.title ?? linked.taskTitle ?? "Task",
                dueDate: dueDate,
                accountKind: foundKind,
                listId: foundListId,
                existingTaskId: linked.taskId
            ))
        }

        taskItems = existingTasks + newTasks
    }

    @State private var isSaving = false

    private func saveGoal() {
        guard let categoryId = selectedCategoryId, !isSaving else { return }
        isSaving = true

        let extData = GoalExtendedData(
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultListId: selectedGoalListId.isEmpty ? nil : selectedGoalListId,
            defaultAccountKind: selectedGoalAccountKind == .personal ? "personal" : "professional"
        )

        let dueDate = calculateDueDate()
        let goalTitle = title
        // Separate existing tasks (already created) from new ones
        let filledTasks = taskItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let newTasks = filledTasks.filter { $0.existingTaskId == nil }
        let existingTasks = filledTasks.filter { $0.existingTaskId != nil }
        let defListId = selectedGoalListId.isEmpty ? defaultListId : selectedGoalListId

        Task {
            // Keep existing linked tasks
            var linkedTasks: [LinkedTaskData] = existingTasks.map { item in
                LinkedTaskData(
                    taskId: item.existingTaskId!,
                    listId: item.listId,
                    accountKind: item.accountKind,
                    taskTitle: item.title
                )
            }

            // Create only new tasks
            for item in newTasks {
                let listId = item.listId.isEmpty ? defListId : item.listId
                let kind = item.accountKind

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let dueDateStr = formatter.string(from: item.dueDate)

                let tempTask = GoogleTask(
                    id: UUID().uuidString,
                    title: item.title,
                    notes: nil,
                    status: "needsAction",
                    due: dueDateStr
                )

                do {
                    let createdTask = try await tasksVM.createTaskOnServer(tempTask, in: listId, for: kind)
                    // Add to local state properly
                    await MainActor.run {
                        switch kind {
                        case .personal:
                            if tasksVM.personalTasks[listId] != nil {
                                // Avoid duplicate — check if already present
                                if !tasksVM.personalTasks[listId]!.contains(where: { $0.id == createdTask.id }) {
                                    tasksVM.personalTasks[listId]?.append(createdTask)
                                }
                            } else {
                                tasksVM.personalTasks[listId] = [createdTask]
                            }
                        case .professional:
                            if tasksVM.professionalTasks[listId] != nil {
                                if !tasksVM.professionalTasks[listId]!.contains(where: { $0.id == createdTask.id }) {
                                    tasksVM.professionalTasks[listId]?.append(createdTask)
                                }
                            } else {
                                tasksVM.professionalTasks[listId] = [createdTask]
                            }
                        }
                    }
                    linkedTasks.append(LinkedTaskData(
                        taskId: createdTask.id,
                        listId: listId,
                        accountKind: kind,
                        taskTitle: createdTask.title
                    ))
                } catch {
                    devLog("Failed to create task '\(item.title)': \(error)", level: .error, category: .tasks)
                }
            }

            await MainActor.run {
                if let existingGoal = editingGoal {
                    var updatedGoal = existingGoal
                    updatedGoal.title = title
                    updatedGoal.categoryId = categoryId
                    updatedGoal.targetTimeframe = selectedTimeframe
                    updatedGoal.dueDate = dueDate
                    updatedGoal.updatedAt = Date()
                    updatedGoal.extendedData = extData
                    updatedGoal.linkedTasks = linkedTasks
                    goalsManager.updateGoal(updatedGoal)
                } else {
                    devLog("Creating goal '\(title)' with \(linkedTasks.count) linked tasks: \(linkedTasks.map { $0.taskId })", level: .info, category: .goals)
                    let newGoal = GoalData(
                        title: title,
                        categoryId: categoryId,
                        targetTimeframe: selectedTimeframe,
                        dueDate: dueDate,
                        linkedTasks: linkedTasks,
                        extendedData: extData
                    )
                    goalsManager.addGoal(newGoal)
                }

                onDismiss()
                dismiss()
            }
        }
    }

    private func deleteGoalWithTasks() {
        if let goal = editingGoal {
            // Delete linked Google Tasks
            for linked in goal.linkedTasks {
                // Search all lists to find the task
                var found = false
                for (listId, tasks) in tasksVM.personalTasks {
                    if let task = tasks.first(where: { $0.id == linked.taskId }) {
                        Task { await tasksVM.deleteTask(task, from: listId, for: .personal) }
                        found = true; break
                    }
                }
                if !found {
                    for (listId, tasks) in tasksVM.professionalTasks {
                        if let task = tasks.first(where: { $0.id == linked.taskId }) {
                            Task { await tasksVM.deleteTask(task, from: listId, for: .professional) }
                            break
                        }
                    }
                }
            }
            goalsManager.deleteGoal(goal.id)
        }
        onDismiss()
        dismiss()
    }

    private func deleteGoalOnly() {
        if let goal = editingGoal {
            goalsManager.deleteGoal(goal.id)
        }
        onDismiss()
        dismiss()
    }

    private func resolvedDueDate(_ item: PendingTask) -> Date {
        if let existingId = item.existingTaskId {
            let result = lookupTask(item)
            return result?.task.dueDate ?? item.dueDate
        }
        return item.dueDate
    }

    private func dueDateTagStyle(_ date: Date, isCompleted: Bool) -> (text: String, textColor: Color, bgColor: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)

        if isCompleted {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        } else if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, .accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        }
    }
}

// MARK: - Task Picker Sheet (3-column: Account → List → Tasks)
struct TaskPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tasksVM: TasksViewModel
    let alreadyLinkedIds: Set<String>
    let onSelect: (GoogleTask, String, GoogleAuthManager.AccountKind) -> Void

    @State private var selectedAccount: GoogleAuthManager.AccountKind? = nil
    @State private var selectedListId: String? = nil

    private var availableAccounts: [GoogleAuthManager.AccountKind] {
        var accounts: [GoogleAuthManager.AccountKind] = []
        if !tasksVM.personalTaskLists.isEmpty { accounts.append(.personal) }
        if !tasksVM.professionalTaskLists.isEmpty { accounts.append(.professional) }
        return accounts
    }

    private var listsForAccount: [GoogleTaskList] {
        guard let account = selectedAccount else { return [] }
        return account == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
    }

    private var tasksForList: [GoogleTask] {
        guard let account = selectedAccount, let listId = selectedListId else { return [] }
        let dict = account == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        return (dict[listId] ?? []).filter { !alreadyLinkedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Column 1: Accounts
                VStack(alignment: .leading, spacing: 0) {
                    Text("Account")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(availableAccounts, id: \.self) { account in
                                Button {
                                    selectedAccount = account
                                    selectedListId = nil
                                } label: {
                                    HStack {
                                        Image(systemName: account == .personal ? "person.fill" : "briefcase.fill")
                                            .font(.caption)
                                        Text(account == .personal ? "Personal" : "Work")
                                            .font(.callout)
                                        Spacer()
                                        if selectedAccount == account {
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedAccount == account ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .frame(minWidth: 120, maxWidth: 140)
                .background(Color(.systemGray6))

                Divider()

                // Column 2: Lists
                VStack(alignment: .leading, spacing: 0) {
                    Text("List")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if selectedAccount == nil {
                        Spacer()
                        Text("Select an account")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(listsForAccount) { list in
                                    Button {
                                        selectedListId = list.id
                                    } label: {
                                        HStack {
                                            Text(list.title)
                                                .font(.callout)
                                                .lineLimit(1)
                                            Spacer()
                                            if selectedListId == list.id {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(selectedListId == list.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(minWidth: 140, maxWidth: 180)
                .background(Color(.systemGray6).opacity(0.5))

                Divider()

                // Column 3: Tasks
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tasks")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if selectedListId == nil {
                        Spacer()
                        Text("Select a list")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if tasksForList.isEmpty {
                        Spacer()
                        Text("No tasks available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(tasksForList) { task in
                                    Button {
                                        onSelect(task, selectedListId!, selectedAccount!)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(task.isCompleted ? .green : .secondary)
                                                .font(.caption)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.title)
                                                    .font(.callout)
                                                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                                                    .strikethrough(task.isCompleted)
                                                    .lineLimit(2)
                                                if let due = task.due {
                                                    Text(String(due.prefix(10)))
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Link Existing Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            // Auto-select first account
            if let first = availableAccounts.first {
                selectedAccount = first
            }
        }
    }
}

// MARK: - Create Category View
struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    @State private var title = ""
    @State private var selectedPosition = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Category name", text: $title)
                }
                
                Section("Position") {
                    Picker("Position in grid", selection: $selectedPosition) {
                        ForEach(0..<6, id: \.self) { position in
                            let row = position / 2
                            let col = position % 2
                            Text("Row \(row + 1), Column \(col + 1)").tag(position)
                        }
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func saveCategory() {
        goalsManager.addCategory(title: title, displayPosition: selectedPosition)
        dismiss()
    }
}

// MARK: - Goal Detail Sheet
struct GoalDetailSheet: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel

    private var category: GoalCategoryData? {
        goalsManager.getCategoryById(goal.categoryId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(goal.title)
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    // Category, Due, Status
                    HStack(spacing: 12) {
                        if let cat = category {
                            tagChip(cat.title, color: .blue)
                        }
                        tagChip(goal.dueDate.formatted(date: .abbreviated, time: .omitted),
                                color: goal.isOverdue ? .red : .green)
                        tagChip(goal.isCompleted ? "Done" : "In Progress",
                                color: goal.isCompleted ? .green : .orange)
                    }

                    // Notes
                    if let ext = goal.extendedData, !ext.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(ext.notes)
                                .font(.body)
                        }
                    }

                    // Linked Tasks
                    if !goal.linkedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tasks")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            ForEach(goal.linkedTasks, id: \.taskId) { linked in
                                let task = findTask(linked.taskId)
                                HStack(spacing: 8) {
                                    Image(systemName: task?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(task?.isCompleted == true ? .green : .secondary)
                                        .font(.body)
                                    Text(task?.title ?? linked.taskTitle ?? "Task")
                                        .font(.body)
                                        .strikethrough(task?.isCompleted == true)
                                    Spacer()
                                    if let due = task?.due {
                                        Text(due.prefix(10))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Search all loaded task lists for a task by ID
    private func findTask(_ taskId: String) -> GoogleTask? {
        for (_, tasks) in tasksVM.personalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return task }
        }
        for (_, tasks) in tasksVM.professionalTasks {
            if let task = tasks.first(where: { $0.id == taskId }) { return task }
        }
        return nil
    }

    private func tagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

// MARK: - Custom Picker Views

// UIPickerView is unsupported under the Mac idiom of Mac Catalyst — adding
// one to a window throws _throwForUnsupportedNonMacIdiomBehavior and crashes
// the app. Substitute the menu style when running on Catalyst.
private extension View {
    @ViewBuilder
    func wheelOrMenuPickerStyle() -> some View {
        #if targetEnvironment(macCatalyst)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }
}

struct YearPickerView: View {
    @Binding var selectedDate: Date
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 10))
    }
    
    var body: some View {
        VStack {
            Text("Year")
                .font(.headline)
                .padding(.bottom, 4)
            
                Picker("Year", selection: Binding(
                    get: { Calendar.current.component(.year, from: selectedDate) },
                    set: { year in
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.month, .day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
            .wheelOrMenuPickerStyle()
        }
    }
}

struct MonthPickerView: View {
    @Binding var selectedDate: Date
    
    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 5))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Year", selection: Binding(
                    get: { Calendar.current.component(.year, from: selectedDate) },
                    set: { year in
                        let calendar = Calendar.current
                        let month = calendar.component(.month, from: selectedDate)
                        let components = calendar.dateComponents([.day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        newComponents.month = month
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
                .wheelOrMenuPickerStyle()
            }
            
            VStack {
                Text("Month")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Month", selection: Binding(
                    get: { Calendar.current.component(.month, from: selectedDate) },
                    set: { month in
                        let calendar = Calendar.current
                        let year = calendar.component(.year, from: selectedDate)
                        let components = calendar.dateComponents([.day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        newComponents.month = month
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(1...12, id: \.self) { month in
                        Text(months[month - 1])
                            .font(.title3)
                            .tag(month)
                    }
                }
                .wheelOrMenuPickerStyle()
            }
        }
        .padding(.vertical, 4)
    }
}

struct WeekPickerView: View {
    @Binding var selectedDate: Date
    
    private let calendar = Calendar.mondayFirst
    @State private var selectedYear: Int
    @State private var selectedWeek: Int
    
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        let currentDate = selectedDate.wrappedValue
        let calendar = Calendar.mondayFirst
        self._selectedYear = State(initialValue: calendar.component(.year, from: currentDate))
        self._selectedWeek = State(initialValue: calendar.component(.weekOfYear, from: currentDate))
    }
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 2))
    }
    
    private var weeks: [(weekNumber: Int, startDate: Date, endDate: Date)] {
        var weeks: [(Int, Date, Date)] = []
        
        let startOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
        let endOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 12, day: 31))!
        
        var currentWeek = startOfYear
        while currentWeek <= endOfYear {
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentWeek) {
                let weekNumber = calendar.component(.weekOfYear, from: currentWeek)
                let endDate = calendar.date(byAdding: .day, value: 6, to: weekInterval.start) ?? weekInterval.end
                weeks.append((weekNumber, weekInterval.start, endDate))
            }
            currentWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek) ?? endOfYear
        }
        
        return weeks
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
                .wheelOrMenuPickerStyle()
                .onChange(of: selectedYear) { _ in
                    updateSelectedDate()
                }
            }
            
            VStack {
                Text("Week")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Week", selection: $selectedWeek) {
                    ForEach(weeks, id: \.weekNumber) { week in
                        let weekText = "WK\(week.weekNumber): \(formatWeekRange(week.startDate, week.endDate))"
                        Text(weekText)
                            .font(.body)
                            .tag(week.weekNumber)
                    }
                }
                .wheelOrMenuPickerStyle()
                .onChange(of: selectedWeek) { _ in
                    updateSelectedDate()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateSelectedDate() {
        if let week = weeks.first(where: { $0.weekNumber == selectedWeek }) {
            selectedDate = week.startDate
        }
    }
    
    private func formatWeekRange(_ startDate: Date, _ endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        return "\(startString) - \(endString)"
    }
}

// MARK: - Goals Summary View
struct GoalsSummaryView: View {
    let completed: Int
    let total: Int
    let currentInterval: TimelineInterval
    let currentDate: Date
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var completionPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    private var timeframeTitle: String {
        let formatter = DateFormatter()
        
        switch currentInterval {
        case .week:
            formatter.dateFormat = "MMM d"
            let startOfWeek = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let endOfWeek = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: startOfWeek) ?? currentDate
            return "Week of \(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: currentDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: currentDate)
        case .day:
            return "All Goals"
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 20
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    var body: some View {
        VStack(spacing: adaptiveSpacing) {
            // Timeframe title
            Text(timeframeTitle)
                .font(horizontalSizeClass == .compact ? .subheadline : .headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Progress bar and stats
            HStack(spacing: 12) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 8)
                            .fill(completionPercentage == 1.0 ? Color.green : Color.blue)
                            .frame(width: geometry.size.width * completionPercentage, height: horizontalSizeClass == .compact ? 12 : 16)
                            .animation(.easeInOut(duration: 0.3), value: completionPercentage)
                    }
                }
                .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                
                // Stats text
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    
                    Text("\(completed)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("/")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(total)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(minWidth: horizontalSizeClass == .compact ? 60 : 80)
            }
            
            // Completion percentage
            if total > 0 {
                Text("\(Int(completionPercentage * 100))% Complete")
                    .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, horizontalSizeClass == .compact ? 12 : 16)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

// MARK: - Preview
#Preview {
    GoalsView()
}
