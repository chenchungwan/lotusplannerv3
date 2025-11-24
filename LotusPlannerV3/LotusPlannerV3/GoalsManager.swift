import Foundation
import CoreData
import CloudKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
        setupiCloudSync()
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
        // Refresh Core Data context to get latest changes from iCloud
        context.refreshAllObjects()
        
        // Load categories
        let categoryRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        categoryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GoalCategory.displayPosition, ascending: true)]
        
        do {
            let coreDataCategories = try context.fetch(categoryRequest)
            let mappedCategories = coreDataCategories.map { entity in
                GoalCategoryData(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    title: entity.title ?? "",
                    displayPosition: Int(entity.displayPosition),
                    createdAt: entity.createdAt ?? Date(),
                    updatedAt: entity.updatedAt ?? Date()
                )
            }
            categories = deduplicatedCategories(from: mappedCategories)
        } catch {
            print("Error loading categories from Core Data: \(error)")
        }
        
        // Load goals
        let goalRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
        goalRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Goal.createdAt, ascending: false)]
        
        do {
            let coreDataGoals = try context.fetch(goalRequest)
            let mappedGoals = coreDataGoals.map { entity in
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
            goals = deduplicatedGoals(from: mappedGoals)
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
        
        let normalizedTitle = normalizeCategoryTitle(title)
        guard !categories.contains(where: { normalizeCategoryTitle($0.title) == normalizedTitle }) else {
            print("Cannot add category: A category with the same name already exists")
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
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    func getCategoryById(_ categoryId: UUID) -> GoalCategoryData? {
        return categories.first { $0.id == categoryId }
    }
    
    // MARK: - Core Data Operations
    private func saveCategoryToCoreData(_ category: GoalCategoryData) {
        // Check if category already exists
        let request: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", category.id.uuidString)
        
        do {
            let existingEntities = try context.fetch(request)
            let entity: GoalCategory
            
            if let existing = existingEntities.first {
                // Update existing category
                entity = existing
            } else {
                // Create new category
                entity = GoalCategory(context: context)
                entity.id = category.id.uuidString
                entity.createdAt = category.createdAt
            }
            
            // Set/update properties
            entity.title = category.title
            entity.displayPosition = Int16(category.displayPosition)
            entity.updatedAt = category.updatedAt
            entity.userId = "default" // You might want to use actual user ID
            
            saveContext()
        } catch {
            print("Error saving category to Core Data: \(error)")
        }
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
        // Check if goal already exists
        let request: NSFetchRequest<Goal> = Goal.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", goal.id.uuidString)
        
        do {
            let existingEntities = try context.fetch(request)
            let entity: Goal
            
            if let existing = existingEntities.first {
                // Update existing goal
                entity = existing
            } else {
                // Create new goal
                entity = Goal(context: context)
                entity.id = goal.id.uuidString
                entity.createdAt = goal.createdAt
            }
            
            // Set/update properties
            entity.title = goal.title
            entity.goalDescription = goal.description
            entity.successMetric = goal.successMetric
            entity.categoryId = goal.categoryId.uuidString
            entity.targetTimeframe = goal.targetTimeframe.rawValue
            entity.dueDate = goal.dueDate
            entity.isCompleted = goal.isCompleted
            entity.updatedAt = goal.updatedAt
            entity.userId = "default" // You might want to use actual user ID
            
            saveContext()
        } catch {
            print("Error saving goal to Core Data: \(error)")
        }
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
    
    // MARK: - Delete All Data
    func deleteAllData() {
        // Clear local arrays
        categories.removeAll()
        goals.removeAll()
        
        // Delete all from Core Data
        let categoryRequest: NSFetchRequest<NSFetchRequestResult> = GoalCategory.fetchRequest()
        let deleteCategoryRequest = NSBatchDeleteRequest(fetchRequest: categoryRequest)
        
        let goalRequest: NSFetchRequest<NSFetchRequestResult> = Goal.fetchRequest()
        let deleteGoalRequest = NSBatchDeleteRequest(fetchRequest: goalRequest)
        
        do {
            try context.execute(deleteCategoryRequest)
            try context.execute(deleteGoalRequest)
            try context.save()
            
            // Clear UserDefaults
            UserDefaults.standard.removeObject(forKey: lastSyncKey)
            
            // Sync deletion to CloudKit
            Task {
                await syncWithiCloud()
            }
        } catch {
            print("Error deleting all goals data: \(error)")
        }
    }
    
    // MARK: - iCloud Sync
    private func syncWithiCloud() async {
        syncStatus = .syncing
        
        do {
            categories = deduplicatedCategories(from: categories)
            goals = deduplicatedGoals(from: goals)
            
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
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .iso8601
                            let container = try decoder.decode(GoalsContainer.self, from: data)
                            
                            // Get sync dates for comparison
                            let cloudSyncDate = record["lastSyncDate"] as? Date ?? Date()
                            let localSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
                            
                            // Update local data if CloudKit data is newer, or if we don't have a local sync date
                            if let localSync = localSyncDate {
                                // We have a local sync date, only update if CloudKit is newer
                                guard cloudSyncDate > localSync else { continue }
                            }
                            // If no local sync date, or CloudKit is newer, update
                            categories = deduplicatedCategories(from: container.categories)
                            goals = deduplicatedGoals(from: container.goals)
                            
                            // Update Core Data
                            await updateCoreDataFromCloudKit()
                            
                            UserDefaults.standard.set(cloudSyncDate, forKey: lastSyncKey)
                        } catch {
                            print("Error decoding goals data from CloudKit: \(error)")
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
    
    // MARK: - iCloud Sync Notifications
    private func setupiCloudSync() {
        // Listen for iCloud data change notifications
        NotificationCenter.default.addObserver(
            forName: .iCloudDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Reload data when iCloud sync completes
            Task { @MainActor in
                self?.loadFromCoreData()
                // Also fetch from CloudKit to ensure we have the latest
                await self?.fetchFromiCloud()
            }
        }
        
        // Listen for Core Data remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Reload data when CloudKit changes are received
            Task { @MainActor in
                self?.loadFromCoreData()
                // Also fetch from CloudKit to ensure we have the latest
                await self?.fetchFromiCloud()
            }
        }
        
        // Fetch from iCloud when app becomes active
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchFromiCloud()
                self?.loadFromCoreData()
            }
        }
        #endif
    }
    
    // MARK: - Public Sync Methods
    func forceSync() async {
        await syncWithiCloud()
    }
    
    func refreshData() {
        loadData()
    }
    
    // MARK: - Data Normalization Helpers
    private func normalizeCategoryTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    private func deduplicatedCategories(from categories: [GoalCategoryData]) -> [GoalCategoryData] {
        var uniqueByTitle: [String: GoalCategoryData] = [:]
        
        for category in categories {
            let key = normalizeCategoryTitle(category.title)
            guard !key.isEmpty else { continue }
            
            if let existing = uniqueByTitle[key] {
                if category.updatedAt > existing.updatedAt {
                    uniqueByTitle[key] = category
                }
            } else {
                uniqueByTitle[key] = category
            }
        }
        
        var deduped = Array(uniqueByTitle.values)
            .sorted {
                if $0.displayPosition == $1.displayPosition {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.displayPosition < $1.displayPosition
            }
        
        var usedPositions = Set<Int>()
        for index in deduped.indices {
            var category = deduped[index]
            if usedPositions.contains(category.displayPosition) {
                if let newPosition = (0..<GoalsManager.maxCategories).first(where: { !usedPositions.contains($0) }) {
                    category.displayPosition = newPosition
                    deduped[index] = category
                    usedPositions.insert(newPosition)
                }
            } else {
                usedPositions.insert(category.displayPosition)
            }
        }
        
        return Array(deduped.prefix(GoalsManager.maxCategories))
    }
    
    private func normalizeGoalTitle(_ title: String) -> String {
        normalizeCategoryTitle(title)
    }
    
    private func deduplicatedGoals(from goals: [GoalData]) -> [GoalData] {
        var uniqueByKey: [String: GoalData] = [:]
        let calendar = Calendar.current
        
        for goal in goals {
            let key = goalDeduplicationKey(for: goal, calendar: calendar)
            guard !key.isEmpty else { continue }
            
            if let existing = uniqueByKey[key] {
                if goal.updatedAt > existing.updatedAt {
                    uniqueByKey[key] = goal
                }
            } else {
                uniqueByKey[key] = goal
            }
        }
        
        return Array(uniqueByKey.values)
            .sorted {
                if $0.categoryId == $1.categoryId {
                    if $0.dueDate == $1.dueDate {
                        return $0.updatedAt > $1.updatedAt
                    }
                    return $0.dueDate < $1.dueDate
                }
                return $0.categoryId.uuidString < $1.categoryId.uuidString
            }
    }
    
    private func goalDeduplicationKey(for goal: GoalData, calendar: Calendar) -> String {
        let normalizedTitle = normalizeGoalTitle(goal.title)
        guard !normalizedTitle.isEmpty else { return "" }
        
        let dayStart = calendar.startOfDay(for: goal.dueDate).timeIntervalSince1970
        return "\(goal.categoryId.uuidString)|\(goal.targetTimeframe.rawValue)|\(normalizedTitle)|\(dayStart)"
    }
}
