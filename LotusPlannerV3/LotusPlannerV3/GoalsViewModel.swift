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
        loadCategories()
        loadGoals()
        setupiCloudSync()
    }

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

    private func setupiCloudSync() {
        // Listen for iCloud data changes
        NotificationCenter.default.addObserver(
            forName: .iCloudDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadCategories()
            self?.loadGoals()
        }
    }

    private func saveCategories() {
        cloudManager.saveGoalCategories(categories)
    }

    private func loadCategories() {
        let loadedCategories = cloudManager.loadGoalCategories()
        if loadedCategories.isEmpty {
            categories = ["Health & Fitness", "Work & Projects", "Family & Friends", "Finances", "Misc."].map { GoalCategory(name: $0) }
            // Save default categories to iCloud
            saveCategories()
        } else {
            categories = loadedCategories
        }
    }

    private func saveGoals() {
        cloudManager.saveGoals(goals)
    }

    private func loadGoals() {
        goals = cloudManager.loadGoals()
    }

    func addGoal(description: String, dueDate: Date?, categoryId: UUID) async {
        let userId = GoogleAuthManager.shared.getEmail(for: .personal)
        let newGoal = Goal(description: description, dueDate: dueDate, categoryId: categoryId, isCompleted: false, userId: userId)
        goals.append(newGoal)
        print("✅ Added goal: \(description)")
    }

    func deleteGoal(_ goal: Goal) async {
        goals.removeAll { $0.id == goal.id }
        print("🗑️ Deleted goal: \(goal.description)")
    }

    func updateGoal(_ goal: Goal) async {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
            print("📝 Updated goal: \(goal.description)")
        }
    }

    func toggleCompletion(_ goal: Goal) async {
        var updated = goal
        updated.isCompleted.toggle()
        await updateGoal(updated)
    }
} 