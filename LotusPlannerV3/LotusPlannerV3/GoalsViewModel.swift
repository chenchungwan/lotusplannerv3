import SwiftUI

struct GoalCategory: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@MainActor
class GoalsViewModel: ObservableObject {
    @Published var categories: [GoalCategory] = [] {
        didSet { saveCategories() }
    }
    @Published var goals: [Goal] = [] {
        didSet { saveGoals() }
    }
    
    private let cloudManager = iCloudManager.shared

    init() {
        loadLocalData()
        setupiCloudSync()
    }
    
    // MARK: - Data Loading and Syncing
    private func loadLocalData() {
        print("📊 Loading local goals data...")
        categories = cloudManager.loadCategories()
        goals = cloudManager.loadGoals()
        
        // Initialize default categories if none exist
        if categories.isEmpty {
            categories = ["Health & Fitness", "Work & Projects", "Family & Friends", "Finances", "Misc."].map { GoalCategory(name: $0) }
        }
        
        print("📊 Loaded \(categories.count) categories and \(goals.count) goals")
    }
    
    private func setupiCloudSync() {
        NotificationCenter.default.addObserver(
            forName: .iCloudDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadLocalData()
            }
        }
    }

    // MARK: - Category Management
    func addCategory(name: String) {
        guard categories.count < 6 else { return }
        categories.append(GoalCategory(name: name))
    }

    func rename(_ category: GoalCategory, to newName: String) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx].name = newName
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }

    private func saveCategories() {
        cloudManager.saveCategories(categories)
    }

    // MARK: - Goal Management
    func addGoal(description: String, dueDate: Date?, categoryId: UUID) {
        let userId = GoogleAuthManager.shared.getEmail(for: .personal) ?? "default_user"
        let newGoal = Goal(description: description, dueDate: dueDate, categoryId: categoryId, isCompleted: false, userId: userId)
        goals.append(newGoal)
        print("✅ Added goal: \(description)")
    }

    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        print("🗑️ Deleted goal: \(goal.id)")
    }

    func updateGoal(_ goal: Goal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
            print("✏️ Updated goal: \(goal.id)")
        }
    }

    func toggleCompletion(_ goal: Goal) {
        var updated = goal
        updated.isCompleted.toggle()
        updateGoal(updated)
    }
    
    private func saveGoals() {
        cloudManager.saveGoals(goals)
    }
} 