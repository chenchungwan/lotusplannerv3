import Foundation
import CoreData
import CloudKit
import SwiftUI

@MainActor
class GoalsManager: ObservableObject {
    static let shared = GoalsManager()
    static let maxCategories = 6
    
    @Published var categories: [GoalCategoryData] = []
    @Published var goals: [GoalData] = []
    @Published var isLoading = false
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
        
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .syncing: return "Syncing..."
            case .success: return "Synced"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    private let persistenceController = PersistenceController.shared
    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private let cloudKitContainer = CKContainer.default()
    private let privateDatabase: CKDatabase
    
    private let categoriesKey = "goalsCategories"
    private let goalsKey = "goals"
    private let lastSyncKey = "goalsLastSync"
    
    private init() {
        self.privateDatabase = cloudKitContainer.privateCloudDatabase
        loadData()
        setupCloudKitSubscription()
    }
    
    // MARK: - Data Loading
    func loadData() {
        isLoading = true
        
        // Load from Core Data first
        loadFromCoreData()
        
        // Then sync with iCloud
        Task {
            await syncWithiCloud()
            isLoading = false
        }
    }
    
    private func loadFromCoreData() {
        // Load categories
        let categoryRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        categoryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GoalCategory.displayPosition, ascending: true)]
        
        do {
            let coreDataCategories = try context.fetch(categoryRequest)
            categories = coreDataCategories.map { entity in
                GoalCategoryData(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    title: entity.title ?? "",
                    displayPosition: Int(entity.displayPosition),
                    createdAt: entity.createdAt ?? Date(),
                    updatedAt: entity.updatedAt ?? Date()
                )
            }
        } catch {
            print("Error loading categories from Core Data: \(error)")
        }
        
        // Load goals
        let goalRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
        goalRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Goal.createdAt, ascending: false)]
        
        do {
            let coreDataGoals = try context.fetch(goalRequest)
            goals = coreDataGoals.map { entity in
                GoalData(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    title: entity.title ?? "",
                    description: entity.goalDescription ?? "",
                    successMetric: entity.successMetric ?? "",
                    categoryId: UUID(uuidString: entity.categoryId ?? "") ?? UUID(),
                    targetTimeframe: GoalTimeframe(rawValue: entity.targetTimeframe ?? "week") ?? .week,
                    dueDate: entity.dueDate ?? Date(),
                    isCompleted: entity.isCompleted,
                    createdAt: entity.createdAt ?? Date(),
                    updatedAt: entity.updatedAt ?? Date()
                )
            }
        } catch {
            print("Error loading goals from Core Data: \(error)")
        }
    }
    
    // MARK: - Category Management
    var canAddCategory: Bool {
        return categories.count < GoalsManager.maxCategories
    }
    
    func addCategory(title: String, displayPosition: Int? = nil) {
        // Check if we've reached the maximum number of categories
        guard canAddCategory else {
            print("Cannot add category: Maximum of \(GoalsManager.maxCategories) categories reached")
            return
        }
        
        let position = displayPosition ?? getNextAvailablePosition()
        let newCategory = GoalCategoryData(
            title: title,
            displayPosition: position
        )
        
        categories.append(newCategory)
        saveCategoryToCoreData(newCategory)
        
        Task {
            await syncWithiCloud()
        }
    }
    
    func updateCategory(_ category: GoalCategoryData) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            updateCategoryInCoreData(category)
            
            Task {
                await syncWithiCloud()
            }
        }
    }
    
    func deleteCategory(_ categoryId: UUID) {
        // Remove category
        categories.removeAll { $0.id == categoryId }
        
        // Remove all goals in this category
        goals.removeAll { $0.categoryId == categoryId }
        
        // Delete from Core Data
        deleteCategoryFromCoreData(categoryId)
        deleteGoalsFromCoreData(categoryId: categoryId)
        
        Task {
            await syncWithiCloud()
        }
    }
    
    func reorderCategories() {
        for (index, category) in categories.enumerated() {
            var updatedCategory = category
            updatedCategory.displayPosition = index
            updatedCategory.updatedAt = Date()
            categories[index] = updatedCategory
            updateCategoryInCoreData(updatedCategory)
        }
        
        Task {
            await syncWithiCloud()
        }
    }
    
    // MARK: - Goal Management
    func addGoal(_ goal: GoalData) {
        goals.append(goal)
        saveGoalToCoreData(goal)
        
        Task {
            await syncWithiCloud()
        }
    }
    
    func updateGoal(_ goal: GoalData) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
            updateGoalInCoreData(goal)
            
            Task {
                await syncWithiCloud()
            }
        }
    }
    
    func deleteGoal(_ goalId: UUID) {
        goals.removeAll { $0.id == goalId }
        deleteGoalFromCoreData(goalId)
        
        Task {
            await syncWithiCloud()
        }
    }
    
    func toggleGoalCompletion(_ goalId: UUID) {
        if let index = goals.firstIndex(where: { $0.id == goalId }) {
            goals[index].isCompleted.toggle()
            goals[index].updatedAt = Date()
            updateGoalInCoreData(goals[index])
            
            Task {
                await syncWithiCloud()
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getNextAvailablePosition() -> Int {
        let usedPositions = Set(categories.map { $0.displayPosition })
        for i in 0..<6 {
            if !usedPositions.contains(i) {
                return i
            }
        }
        return categories.count
    }
    
    func getGoalsForCategory(_ categoryId: UUID) -> [GoalData] {
        return goals.filter { $0.categoryId == categoryId }
    }
    
    func getCategoryById(_ categoryId: UUID) -> GoalCategoryData? {
        return categories.first { $0.id == categoryId }
    }
    
    // MARK: - Core Data Operations
    private func saveCategoryToCoreData(_ category: GoalCategoryData) {
        let entity = GoalCategory(context: context)
        entity.id = category.id.uuidString
        entity.title = category.title
        entity.displayPosition = Int16(category.displayPosition)
        entity.createdAt = category.createdAt
        entity.updatedAt = category.updatedAt
        entity.userId = "default" // You might want to use actual user ID
        
        saveContext()
    }
    
    private func updateCategoryInCoreData(_ category: GoalCategoryData) {
        let request: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", category.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            if let entity = entities.first {
                entity.title = category.title
                entity.displayPosition = Int16(category.displayPosition)
                entity.updatedAt = category.updatedAt
                saveContext()
            }
        } catch {
            print("Error updating category in Core Data: \(error)")
        }
    }
    
    private func deleteCategoryFromCoreData(_ categoryId: UUID) {
        let request: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", categoryId.uuidString)
        
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            saveContext()
        } catch {
            print("Error deleting category from Core Data: \(error)")
        }
    }
    
    private func saveGoalToCoreData(_ goal: GoalData) {
        let entity = Goal(context: context)
        entity.id = goal.id.uuidString
        entity.title = goal.title
        entity.goalDescription = goal.description
        entity.successMetric = goal.successMetric
        entity.categoryId = goal.categoryId.uuidString
        entity.targetTimeframe = goal.targetTimeframe.rawValue
        entity.dueDate = goal.dueDate
        entity.isCompleted = goal.isCompleted
        entity.createdAt = goal.createdAt
        entity.updatedAt = goal.updatedAt
        entity.userId = "default" // You might want to use actual user ID
        
        saveContext()
    }
    
    private func updateGoalInCoreData(_ goal: GoalData) {
        let request: NSFetchRequest<Goal> = Goal.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", goal.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            if let entity = entities.first {
                entity.title = goal.title
                entity.goalDescription = goal.description
                entity.successMetric = goal.successMetric
                entity.categoryId = goal.categoryId.uuidString
                entity.targetTimeframe = goal.targetTimeframe.rawValue
                entity.dueDate = goal.dueDate
                entity.isCompleted = goal.isCompleted
                entity.updatedAt = goal.updatedAt
                saveContext()
            }
        } catch {
            print("Error updating goal in Core Data: \(error)")
        }
    }
    
    private func deleteGoalFromCoreData(_ goalId: UUID) {
        let request: NSFetchRequest<Goal> = Goal.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", goalId.uuidString)
        
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            saveContext()
        } catch {
            print("Error deleting goal from Core Data: \(error)")
        }
    }
    
    private func deleteGoalsFromCoreData(categoryId: UUID) {
        let request: NSFetchRequest<Goal> = Goal.fetchRequest()
        request.predicate = NSPredicate(format: "categoryId == %@", categoryId.uuidString)
        
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            saveContext()
        } catch {
            print("Error deleting goals from Core Data: \(error)")
        }
    }
    
    private func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    // MARK: - iCloud Sync
    private func syncWithiCloud() async {
        syncStatus = .syncing
        
        do {
            // Create container for sync
            let container = GoalsContainer(
                categories: categories,
                goals: goals,
                lastSyncDate: Date()
            )
            
            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(container)
            
            // Save to CloudKit
            let record = CKRecord(recordType: "GoalsData")
            record["data"] = data
            record["lastSyncDate"] = Date()
            
            try await privateDatabase.save(record)
            
            // Also try to fetch any updates from CloudKit
            await fetchFromiCloud()
            
            syncStatus = .success
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Error syncing with iCloud: \(error)")
        }
    }
    
    private func fetchFromiCloud() async {
        do {
            let query = CKQuery(recordType: "GoalsData", predicate: NSPredicate(value: true))
            let results = try await privateDatabase.records(matching: query)
            
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let data = record["data"] as? Data {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let container = try decoder.decode(GoalsContainer.self, from: data)
                        
                        // Update local data if CloudKit data is newer
                        if let cloudSyncDate = record["lastSyncDate"] as? Date,
                           let localSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
                           cloudSyncDate > localSyncDate {
                            
                            categories = container.categories
                            goals = container.goals
                            
                            // Update Core Data
                            await updateCoreDataFromCloudKit()
                            
                            UserDefaults.standard.set(cloudSyncDate, forKey: lastSyncKey)
                        }
                    }
                case .failure(let error):
                    print("Error fetching record: \(error)")
                }
            }
        } catch {
            print("Error fetching from iCloud: \(error)")
        }
    }
    
    private func updateCoreDataFromCloudKit() async {
        // Clear existing data
        let categoryRequest: NSFetchRequest<NSFetchRequestResult> = GoalCategory.fetchRequest()
        let deleteCategoryRequest = NSBatchDeleteRequest(fetchRequest: categoryRequest)
        
        let goalRequest: NSFetchRequest<NSFetchRequestResult> = Goal.fetchRequest()
        let deleteGoalRequest = NSBatchDeleteRequest(fetchRequest: goalRequest)
        
        do {
            try context.execute(deleteCategoryRequest)
            try context.execute(deleteGoalRequest)
            
            // Save new data
            for category in categories {
                saveCategoryToCoreData(category)
            }
            
            for goal in goals {
                saveGoalToCoreData(goal)
            }
        } catch {
            print("Error updating Core Data from CloudKit: \(error)")
        }
    }
    
    private func setupCloudKitSubscription() {
        // Set up CloudKit subscription for real-time updates
        let subscription = CKQuerySubscription(
            recordType: "GoalsData",
            predicate: NSPredicate(value: true),
            subscriptionID: "goals-data-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        Task {
            do {
                try await privateDatabase.save(subscription)
            } catch {
                print("Error setting up CloudKit subscription: \(error)")
            }
        }
    }
    
    // MARK: - Public Sync Methods
    func forceSync() async {
        await syncWithiCloud()
    }
    
    func refreshData() {
        loadData()
    }
}
