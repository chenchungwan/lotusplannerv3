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
    private let storageKey = "goalCategories"
    init() {
        loadCategories()
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
} 