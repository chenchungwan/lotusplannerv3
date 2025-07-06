import SwiftUI
import FirebaseFirestore

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
    @Published var goals: [Goal] = []
    private let storageKey = "goalCategories"
    private let firestore = FirestoreManager.shared

    init() {
        loadCategories()
        Task { await loadGoals() }
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

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([GoalCategory].self, from: data) {
            categories = decoded
        } else {
            categories = ["Health & Fitness", "Work & Projects", "Family & Friends", "Finances", "Misc."].map { GoalCategory(name: $0) }
            // Fill up to 6 with blanks
        }
    }

    func loadGoals() async {
        do {
            let fetched = try await firestore.loadGoals()
            await MainActor.run { goals = fetched }
        } catch {
            print("Failed to load goals: \(error)")
        }
    }

    func addGoal(description: String, dueDate: Date?, categoryId: UUID) async {
        let userId = GoogleAuthManager.shared.getEmail(for: .personal)
        let newGoal = Goal(description: description, dueDate: dueDate, categoryId: categoryId, userId: userId)
        await MainActor.run { goals.append(newGoal) } // optimistic UI update
        do {
            try await firestore.addGoal(newGoal)
            // Success: we already added locally, no immediate reload needed.
        } catch {
            print("add goal error \(error)")
        }
    }

    func deleteGoal(_ goal: Goal) async {
        await MainActor.run { goals.removeAll { $0.id == goal.id } }
        do {
            try await firestore.deleteGoal(goal.id)
            await loadGoals()
        } catch {
            print("delete goal error \(error)")
        }
    }

    func updateGoal(_ goal: Goal) async {
        await MainActor.run {
            if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[idx] = goal
            }
        }
        do {
            try await firestore.updateGoal(goal)
            await loadGoals()
        } catch {
            print("update goal error \(error)")
        }
    }
} 