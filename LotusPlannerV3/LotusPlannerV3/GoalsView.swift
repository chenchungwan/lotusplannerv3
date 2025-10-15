import SwiftUI

enum GoalFilter: String, CaseIterable {
    case all = "all"
    case hasDueDate = "hasDueDate"
    case noDueDate = "noDueDate"
    case completed = "completed"
    case overdue = "overdue"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .hasDueDate: return "Has Due Date"
        case .noDueDate: return "No Due Date"
        case .completed: return "Completed"
        case .overdue: return "Overdue"
        }
    }
}

struct GoalsView: View {
    @ObservedObject private var viewModel = DataManager.shared.goalsViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var showingEditGoal = false
    @State private var selectedGoalForEdit: Goal?
    @State private var selectedCategoryForEdit: UUID?
    
    // Filtering state
    @State private var currentFilter: GoalFilter = .all
    @State private var currentTimeframeFilter: String? = nil
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    // Filtered categories based on current filters
    private var filteredCategories: [GoalCategory] {
        var filtered = viewModel.categories
        
        // Apply status filtering
        switch currentFilter {
        case .all:
            break
        case .hasDueDate:
            filtered = filtered.map { category in
                var filteredCategory = category
                filteredCategory.goals = category.goals.filter { goal in
                    // Goals with due dates (not the default calculated date)
                    let calendar = Calendar.current
                    let now = Date()
                    let defaultDueDate = calculateDefaultDueDate(for: goal.timeframe, from: now)
                    return goal.dueDate != defaultDueDate
                }
                return filteredCategory
            }
        case .noDueDate:
            filtered = filtered.map { category in
                var filteredCategory = category
                filteredCategory.goals = category.goals.filter { goal in
                    // Goals without due dates (using default calculated date)
                    let calendar = Calendar.current
                    let now = Date()
                    let defaultDueDate = calculateDefaultDueDate(for: goal.timeframe, from: now)
                    return goal.dueDate == defaultDueDate
                }
                return filteredCategory
            }
        case .completed:
            filtered = filtered.map { category in
                var filteredCategory = category
                filteredCategory.goals = category.goals.filter { $0.isCompleted }
                return filteredCategory
            }
        case .overdue:
            filtered = filtered.map { category in
                var filteredCategory = category
                filteredCategory.goals = category.goals.filter { goal in
                    !goal.isCompleted && goal.dueDate < Date()
                }
                return filteredCategory
            }
        }
        
        // Apply timeframe filtering
        if let timeframe = currentTimeframeFilter {
            filtered = filtered.map { category in
                var filteredCategory = category
                filteredCategory.goals = category.goals.filter { goal in
                    goal.timeframe.rawValue == timeframe
                }
                return filteredCategory
            }
        }
        
        return filtered
    }
    
    private func calculateDefaultDueDate(for timeframe: Timeframe, from date: Date) -> Date {
        let calendar = Calendar.current
        
        switch timeframe {
        case .week:
            // Due at end of current week (Sunday)
            let weekday = calendar.component(.weekday, from: date)
            let daysUntilSunday = (7 - weekday) % 7
            return calendar.date(byAdding: .day, value: daysUntilSunday, to: date) ?? date
        case .month:
            // Due at end of current month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
            let startOfNextMonth = calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
            return calendar.date(byAdding: .day, value: -1, to: startOfNextMonth) ?? date
        case .year:
            // Due at end of current year
            let nextYear = calendar.date(byAdding: .year, value: 1, to: date) ?? date
            let startOfNextYear = calendar.dateInterval(of: .year, for: nextYear)?.start ?? nextYear
            return calendar.date(byAdding: .day, value: -1, to: startOfNextYear) ?? date
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Filter Status Display (for testing)
            if currentFilter != .all || currentTimeframeFilter != nil {
                HStack {
                    Text("Filter: ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if currentFilter != .all {
                        Text(currentFilter.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if let timeframe = currentTimeframeFilter {
                        Text(timeframe.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Test buttons for filtering
                    HStack(spacing: 8) {
                        Button("W") {
                            currentTimeframeFilter = "week"
                            currentFilter = .all
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Button("M") {
                            currentTimeframeFilter = "month"
                            currentFilter = .all
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Button("Y") {
                            currentTimeframeFilter = "year"
                            currentFilter = .all
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Button("All") {
                            currentFilter = .all
                            currentTimeframeFilter = nil
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                        
                        Button("Comp") {
                            currentFilter = .completed
                            currentTimeframeFilter = nil
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                        
                        Button("Over") {
                            currentFilter = .overdue
                            currentTimeframeFilter = nil
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        
                        Button("Clear") {
                            currentFilter = .all
                            currentTimeframeFilter = nil
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            
            // Main Content
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(filteredCategories) { category in
                            GoalCategoryCard(
                                category: category,
                                onRename: { newName in
                                    viewModel.renameCategory(category.id, to: newName)
                                },
                                onAddGoal: { goalTitle, timeframe in
                                    viewModel.addGoal(to: category.id, title: goalTitle, timeframe: timeframe)
                                },
                                onToggleGoal: { goalId in
                                    viewModel.toggleGoalCompletion(goalId, in: category.id)
                                },
                                onDeleteGoal: { goalId in
                                    viewModel.deleteGoal(goalId, from: category.id)
                                },
                                onEditGoal: { goalId, newTitle in
                                    viewModel.editGoal(goalId, in: category.id, newTitle: newTitle)
                                },
                                onDeleteCategory: {
                                    viewModel.deleteCategory(category.id)
                                },
                                onTapGoal: { goal in
                                    selectedGoalForEdit = goal
                                    selectedCategoryForEdit = category.id
                                    showingEditGoal = true
                                }
                            )
                            .frame(height: geometry.size.height / 3 - 16)
                            .onDrag {
                                viewModel.draggingCategory = category
                                return NSItemProvider(object: category.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: GoalCategoryDropDelegate(
                                category: category,
                                categories: $viewModel.categories,
                                draggingCategory: $viewModel.draggingCategory
                            ))
                        }
                        
                        // Add Category Card
                        AddCategoryCard(
                            onAddCategory: { categoryName in
                                viewModel.addCategory(title: categoryName)
                            }
                        )
                        .frame(height: geometry.size.height / 3 - 16)
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showingEditGoal) {
            if let goal = selectedGoalForEdit, let categoryId = selectedCategoryForEdit {
                EditGoalView(
                    goal: goal,
                    categoryId: categoryId,
                    onDelete: { goalId in
                        viewModel.deleteGoal(goalId, from: categoryId)
                    }
                )
            }
        }
        .onChange(of: showingEditGoal) { _, newValue in
            if !newValue {
                // Reset state when sheet is dismissed
                selectedGoalForEdit = nil
                selectedCategoryForEdit = nil
            }
        }
        .onAppear {
            setupNotificationListeners()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FilterGoalsByStatus"))) { notification in
            if let status = notification.object as? String {
                currentFilter = GoalFilter(rawValue: status) ?? .all
                currentTimeframeFilter = nil // Clear timeframe filter when status filter is applied
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FilterGoalsByTimeframe"))) { notification in
            if let timeframe = notification.object as? String {
                currentTimeframeFilter = timeframe
                currentFilter = .all // Clear status filter when timeframe filter is applied
            }
        }
    }
    
    private func setupNotificationListeners() {
        // Notification listeners are set up via onReceive modifiers
    }
}

// MARK: - Goal Category Card
struct GoalCategoryCard: View {
    let category: GoalCategory
    let onRename: (String) -> Void
    let onAddGoal: (String, Timeframe) -> Void
    let onToggleGoal: (UUID) -> Void
    let onDeleteGoal: (UUID) -> Void
    let onEditGoal: (UUID, String) -> Void
    let onDeleteCategory: () -> Void
    let onTapGoal: (Goal) -> Void
    
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingAddGoal = false
    @State private var newGoalTitle = ""
    @State private var selectedTimeframe: Timeframe = .year
    @State private var editingGoalId: UUID?
    @State private var editingGoalText = ""
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Text(category.title)
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
                
                // Delete category button
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
            
            // Goals list
            ScrollView {
                VStack(spacing: 8) {
                    // Add goal input (when active)
                    if showingAddGoal {
                        VStack(spacing: 8) {
                            TextField("New goal", text: $newGoalTitle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    addNewGoal()
                                }
                            
                            // Timeframe selection
                            HStack {
                                Text("Timeframe:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("Timeframe", selection: $selectedTimeframe) {
                                    ForEach(Timeframe.allCases, id: \.self) { timeframe in
                                        Text(timeframe.displayName).tag(timeframe)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(maxWidth: 200)
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 8) {
                                Button("Add") {
                                    addNewGoal()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .disabled(newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                Button("Cancel") {
                                    showingAddGoal = false
                                    newGoalTitle = ""
                                    selectedTimeframe = .year
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    // Existing goals
                    ForEach(category.goals) { goal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                // Checkbox
                                Button(action: {
                                    onToggleGoal(goal.id)
                                }) {
                                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.body)
                                        .foregroundColor(goal.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                
                                // Goal title (editable on tap)
                                if editingGoalId == goal.id {
                                    TextField("Goal", text: $editingGoalText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onSubmit {
                                            saveGoalEdit()
                                        }
                                    
                                    Button("Save") {
                                        saveGoalEdit()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                } else {
                                    Text(goal.title)
                                        .font(.body)
                                        .strikethrough(goal.isCompleted)
                                        .foregroundColor(goal.isCompleted ? .secondary : .primary)
                                        .lineLimit(2)
                                        .onTapGesture {
                                            onTapGoal(goal)
                                        }
                                }
                            }
                            
                            // Goal details
                            HStack {
                                // Timeframe badge
                                Text(goal.timeframe.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                                
                                // Due date
                                Text("Due: \(goal.dueDate, formatter: DateFormatter.shortDate)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // Completion status
                                if goal.isCompleted {
                                    Text("Completed")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.leading, 24) // Align with goal title
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    
                    if category.goals.isEmpty && !showingAddGoal {
                        Text("No goals yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .alert("Delete Category", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDeleteCategory()
            }
        } message: {
            Text("Are you sure you want to delete '\(category.title)'? All goals in this category will be deleted.")
        }
    }
    
    private func startEditingTitle() {
        editedTitle = category.title
        isEditingTitle = true
    }
    
    private func saveCategoryTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditingTitle = false
    }
    
    private func addNewGoal() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onAddGoal(trimmed, selectedTimeframe)
            newGoalTitle = ""
            selectedTimeframe = .year
            showingAddGoal = false
        }
    }
    
    private func startEditingGoal(_ goal: Goal) {
        editingGoalId = goal.id
        editingGoalText = goal.title
    }
    
    private func saveGoalEdit() {
        if let goalId = editingGoalId {
            let trimmed = editingGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onEditGoal(goalId, trimmed)
            }
        }
        editingGoalId = nil
        editingGoalText = ""
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

// MARK: - Drag and Drop Delegate
struct GoalCategoryDropDelegate: DropDelegate {
    let category: GoalCategory
    @Binding var categories: [GoalCategory]
    @Binding var draggingCategory: GoalCategory?
    
    func performDrop(info: DropInfo) -> Bool {
        draggingCategory = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingCategory = draggingCategory,
              draggingCategory.id != category.id,
              let fromIndex = categories.firstIndex(where: { $0.id == draggingCategory.id }),
              let toIndex = categories.firstIndex(where: { $0.id == category.id }) else {
            return
        }
        
        withAnimation {
            categories.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}

// MARK: - Data Models
enum Timeframe: String, CaseIterable, Codable {
    case week = "week"
    case month = "month"
    case year = "year"
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var category: String
    var timeframe: Timeframe
    var dueDate: Date
    var isCompleted: Bool
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, category: String, timeframe: Timeframe, dueDate: Date, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.category = category
        self.timeframe = timeframe
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

struct GoalCategory: Identifiable, Codable {
    let id: UUID
    var title: String
    var goals: [Goal]
    var position: Int
    
    init(id: UUID = UUID(), title: String, goals: [Goal] = [], position: Int = 0) {
        self.id = id
        self.title = title
        self.goals = goals
        self.position = position
    }
}

// MARK: - View Model
@MainActor
class GoalsViewModel: ObservableObject {
    @Published var categories: [GoalCategory] = []
    @Published var draggingCategory: GoalCategory?
    
    private let userDefaults = UserDefaults.standard
    private let categoriesKey = "goalsCategories"
    
    init() {
        loadCategories()
        
        // If no categories exist, create default 6 categories
        if categories.isEmpty {
            categories = [
                GoalCategory(id: UUID(), title: "Health & Fitness", position: 0),
                GoalCategory(id: UUID(), title: "Career", position: 1),
                GoalCategory(id: UUID(), title: "Personal Growth", position: 2),
                GoalCategory(id: UUID(), title: "Relationships", position: 3),
                GoalCategory(id: UUID(), title: "Finance", position: 4),
                GoalCategory(id: UUID(), title: "Hobbies", position: 5)
            ]
            saveCategories()
        }
    }
    
    func renameCategory(_ id: UUID, to newName: String) {
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].title = newName
            saveCategories()
        }
    }
    
    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        saveCategories()
    }
    
    func addCategory(title: String) {
        let newPosition = categories.map { $0.position }.max() ?? -1
        let newCategory = GoalCategory(title: title, position: newPosition + 1)
        categories.append(newCategory)
        saveCategories()
    }
    
    func addGoal(to categoryId: UUID, title: String, timeframe: Timeframe = .year) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            let categoryTitle = categories[index].title
            let dueDate = calculateDueDate(for: timeframe)
            let newGoal = Goal(title: title, category: categoryTitle, timeframe: timeframe, dueDate: dueDate)
            categories[index].goals.append(newGoal)
            saveCategories()
        }
    }
    
    private func calculateDueDate(for timeframe: Timeframe) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeframe {
        case .week:
            // Due at end of current week (Sunday)
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilSunday = (7 - weekday) % 7
            return calendar.date(byAdding: .day, value: daysUntilSunday, to: now) ?? now
        case .month:
            // Due at end of current month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            let startOfNextMonth = calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
            return calendar.date(byAdding: .day, value: -1, to: startOfNextMonth) ?? now
        case .year:
            // Due at end of current year
            let nextYear = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            let startOfNextYear = calendar.dateInterval(of: .year, for: nextYear)?.start ?? nextYear
            return calendar.date(byAdding: .day, value: -1, to: startOfNextYear) ?? now
        }
    }
    
    func toggleGoalCompletion(_ goalId: UUID, in categoryId: UUID) {
        if let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }),
           let goalIndex = categories[categoryIndex].goals.firstIndex(where: { $0.id == goalId }) {
            categories[categoryIndex].goals[goalIndex].isCompleted.toggle()
            saveCategories()
        }
    }
    
    func deleteGoal(_ goalId: UUID, from categoryId: UUID) {
        if let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[categoryIndex].goals.removeAll { $0.id == goalId }
            saveCategories()
        }
    }
    
    func editGoal(_ goalId: UUID, in categoryId: UUID, newTitle: String) {
        if let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }),
           let goalIndex = categories[categoryIndex].goals.firstIndex(where: { $0.id == goalId }) {
            categories[categoryIndex].goals[goalIndex].title = newTitle
            saveCategories()
        }
    }
    
    func updateGoalTimeframe(_ goalId: UUID, in categoryId: UUID, newTimeframe: Timeframe) {
        if let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }),
           let goalIndex = categories[categoryIndex].goals.firstIndex(where: { $0.id == goalId }) {
            categories[categoryIndex].goals[goalIndex].timeframe = newTimeframe
            categories[categoryIndex].goals[goalIndex].dueDate = calculateDueDate(for: newTimeframe)
            saveCategories()
        }
    }
    
    func updateGoalDueDate(_ goalId: UUID, in categoryId: UUID, newDueDate: Date) {
        if let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }),
           let goalIndex = categories[categoryIndex].goals.firstIndex(where: { $0.id == goalId }) {
            categories[categoryIndex].goals[goalIndex].dueDate = newDueDate
            saveCategories()
        }
    }
    
    func saveCategories() {
        if let encoded = try? JSONEncoder().encode(categories) {
            userDefaults.set(encoded, forKey: categoriesKey)
        }
    }
    
    private func loadCategories() {
        if let data = userDefaults.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([GoalCategory].self, from: data) {
            categories = decoded.sorted { $0.position < $1.position }
        }
    }
}

// MARK: - Preview
#Preview {
    GoalsView()
}

