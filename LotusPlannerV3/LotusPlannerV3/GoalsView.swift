import SwiftUI

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
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
                        ForEach(viewModel.categories) { category in
                            GoalCategoryCard(
                                category: category,
                                onRename: { newName in
                                    viewModel.renameCategory(category.id, to: newName)
                                },
                                onAddGoal: { goalTitle in
                                    viewModel.addGoal(to: category.id, title: goalTitle)
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
    }
}

// MARK: - Goal Category Card
struct GoalCategoryCard: View {
    let category: GoalCategory
    let onRename: (String) -> Void
    let onAddGoal: (String) -> Void
    let onToggleGoal: (UUID) -> Void
    let onDeleteGoal: (UUID) -> Void
    let onEditGoal: (UUID, String) -> Void
    let onDeleteCategory: () -> Void
    
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingAddGoal = false
    @State private var newGoalTitle = ""
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
                
                // Add goal button
                Button(action: {
                    showingAddGoal = true
                    newGoalTitle = ""
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
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
                        HStack(spacing: 8) {
                            TextField("New goal", text: $newGoalTitle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    addNewGoal()
                                }
                            
                            Button("Add") {
                                addNewGoal()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .disabled(newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button("Cancel") {
                                showingAddGoal = false
                                newGoalTitle = ""
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    // Existing goals
                    ForEach(category.goals) { goal in
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
                                        startEditingGoal(goal)
                                    }
                                
                                Spacer()
                                
                                // Delete button
                                Button(action: {
                                    onDeleteGoal(goal.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
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
            onAddGoal(trimmed)
            newGoalTitle = ""
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
struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
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
    
    func addGoal(to categoryId: UUID, title: String) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            let newGoal = Goal(title: title)
            categories[index].goals.append(newGoal)
            saveCategories()
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
    
    private func saveCategories() {
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

