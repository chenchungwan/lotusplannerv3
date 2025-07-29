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
    
    private let coreDataManager = CoreDataManager.shared

    init() {
        loadLocalData()
        setupiCloudSync()
    }
    
    // MARK: - Data Loading and Syncing
    private func loadLocalData() {
        print("📊 Loading local goals data from Core Data...")
        
        categories = coreDataManager.loadCategories()
        goals = coreDataManager.loadGoals()
        
        // Initialize default categories if none exist
        if categories.isEmpty {
            let defaultCategories = ["Health & Fitness", "Work & Projects", "Family & Friends", "Finances", "Misc."].map { GoalCategory(name: $0) }
            
            // Save default categories to Core Data
            for category in defaultCategories {
                coreDataManager.saveCategory(category)
            }
            
            categories = defaultCategories
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
        let newCategory = GoalCategory(name: name)
        
        // Save to Core Data
        coreDataManager.saveCategory(newCategory)
        
        // Update local array
        categories.append(newCategory)
    }

    func rename(_ category: GoalCategory, to newName: String) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx].name = newName
            
            // Update in Core Data
            coreDataManager.updateCategory(categories[idx])
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }

    private func saveCategories() {
        // Individual categories are saved immediately when modified in Core Data
        // No batch save needed
    }

    // MARK: - Goal Management
    func addGoal(description: String, dueDate: Date?, categoryId: UUID) {
        let userId = GoogleAuthManager.shared.getEmail(for: .personal) ?? "default_user"
        let newGoal = Goal(description: description, dueDate: dueDate, categoryId: categoryId, isCompleted: false, userId: userId)
        
        // Save to Core Data
        coreDataManager.saveGoal(newGoal)
        
        // Update local array
        goals.append(newGoal)
        print("✅ Added goal: \(description)")
    }

    func deleteGoal(_ goal: Goal) {
        // Delete from Core Data
        coreDataManager.deleteGoal(goal)
        
        // Update local array
        goals.removeAll { $0.id == goal.id }
        print("🗑️ Deleted goal: \(goal.id)")
    }

    func updateGoal(_ goal: Goal) {
        // Update in Core Data
        coreDataManager.updateGoal(goal)
        
        // Update local array
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
        // Individual goals are saved immediately when modified in Core Data
        // No batch save needed
    }
} 