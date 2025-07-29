import Foundation
import CoreData
import SwiftUI

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    private let persistenceController = PersistenceController.shared
    
    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private init() {}
    
    // MARK: - Save Context
    private func save() {
        if context.hasChanges {
            do {
                try context.save()
                print("✅ Core Data saved successfully")
            } catch {
                print("❌ Core Data save failed: \(error)")
            }
        }
    }
    
    // MARK: - Weight Logs
    func saveWeightEntry(_ entry: WeightLogEntry) {
        let weightLog = WeightLog(context: context)
        weightLog.id = entry.id
        weightLog.timestamp = entry.timestamp
        weightLog.weight = entry.weight
        weightLog.unit = entry.unit.rawValue
        weightLog.userId = entry.userId
        
        save()
    }
    
    func loadWeightEntries() -> [WeightLogEntry] {
        let request: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeightLog.timestamp, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let timestamp = log.timestamp,
                      let unitString = log.unit,
                      let unit = WeightUnit(rawValue: unitString),
                      let userId = log.userId else { return nil }
                
                return WeightLogEntry(
                    id: id,
                    timestamp: timestamp,
                    weight: log.weight,
                    unit: unit,
                    userId: userId
                )
            }
        } catch {
            print("❌ Failed to load weight entries: \(error)")
            return []
        }
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        let request: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)
        
        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
            print("❌ Failed to delete weight entry: \(error)")
        }
    }
    
    // MARK: - Workout Logs
    func saveWorkoutEntry(_ entry: WorkoutLogEntry) {
        let workoutLog = WorkoutLog(context: context)
        workoutLog.id = entry.id
        workoutLog.date = entry.date
        workoutLog.name = entry.name
        workoutLog.userId = entry.userId
        workoutLog.createdAt = entry.createdAt
        
        save()
    }
    
    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.date, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let name = log.name,
                      let userId = log.userId,
                      let createdAt = log.createdAt else { return nil }
                
                return WorkoutLogEntry(
                    id: id,
                    date: date,
                    name: name,
                    userId: userId,
                    createdAt: createdAt
                )
            }
        } catch {
            print("❌ Failed to load workout entries: \(error)")
            return []
        }
    }
    
    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)
        
        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
            print("❌ Failed to delete workout entry: \(error)")
        }
    }
    
    // MARK: - Food Logs
    func saveFoodEntry(_ entry: FoodLogEntry) {
        let foodLog = FoodLog(context: context)
        foodLog.id = entry.id
        foodLog.date = entry.date
        foodLog.name = entry.name
        foodLog.userId = entry.userId
        foodLog.createdAt = entry.createdAt
        
        save()
    }
    
    func loadFoodEntries() -> [FoodLogEntry] {
        let request: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FoodLog.date, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let name = log.name,
                      let userId = log.userId,
                      let createdAt = log.createdAt else { return nil }
                
                return FoodLogEntry(
                    id: id,
                    date: date,
                    name: name,
                    userId: userId,
                    createdAt: createdAt
                )
            }
        } catch {
            print("❌ Failed to load food entries: \(error)")
            return []
        }
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        let request: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)
        
        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
            print("❌ Failed to delete food entry: \(error)")
        }
    }
    
    // MARK: - Goals
    func saveGoal(_ goal: Goal) {
        let goalEntity = GoalEntity(context: context)
        goalEntity.id = goal.id.uuidString
        goalEntity.desc = goal.description
        goalEntity.dueDate = goal.dueDate
        goalEntity.categoryId = goal.categoryId.uuidString
        goalEntity.isCompleted = goal.isCompleted
        goalEntity.userId = goal.userId
        goalEntity.createdAt = goal.createdAt
        
        save()
    }
    
    func loadGoals() -> [Goal] {
        let request: NSFetchRequest<GoalEntity> = GoalEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { entity in
                guard let idString = entity.id,
                      let id = UUID(uuidString: idString),
                      let description = entity.desc,
                      let categoryIdString = entity.categoryId,
                      let categoryId = UUID(uuidString: categoryIdString),
                      let userId = entity.userId,
                      let createdAt = entity.createdAt else { return nil }
                
                return Goal(
                    id: id,
                    description: description,
                    dueDate: entity.dueDate,
                    categoryId: categoryId,
                    isCompleted: entity.isCompleted,
                    taskLinks: [], // TaskLinks not stored in Core Data yet
                    userId: userId,
                    createdAt: createdAt
                )
            }
        } catch {
            print("❌ Failed to load goals: \(error)")
            return []
        }
    }
    
    func updateGoal(_ goal: Goal) {
        let request: NSFetchRequest<GoalEntity> = GoalEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", goal.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            if let entity = entities.first {
                entity.desc = goal.description
                entity.dueDate = goal.dueDate
                entity.categoryId = goal.categoryId.uuidString
                entity.isCompleted = goal.isCompleted
                save()
            }
        } catch {
            print("❌ Failed to update goal: \(error)")
        }
    }
    
    func deleteGoal(_ goal: Goal) {
        let request: NSFetchRequest<GoalEntity> = GoalEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", goal.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            entities.forEach(context.delete)
            save()
        } catch {
            print("❌ Failed to delete goal: \(error)")
        }
    }
    
    // MARK: - Goal Categories
    func saveCategory(_ category: GoalCategory) {
        let categoryEntity = GoalCategoryEntity(context: context)
        categoryEntity.id = category.id.uuidString
        categoryEntity.name = category.name
        
        save()
    }
    
    func loadCategories() -> [GoalCategory] {
        let request: NSFetchRequest<GoalCategoryEntity> = GoalCategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GoalCategoryEntity.name, ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { entity in
                guard let idString = entity.id,
                      let id = UUID(uuidString: idString),
                      let name = entity.name else { return nil }
                
                return GoalCategory(id: id, name: name)
            }
        } catch {
            print("❌ Failed to load categories: \(error)")
            return []
        }
    }
    
    func updateCategory(_ category: GoalCategory) {
        let request: NSFetchRequest<GoalCategoryEntity> = GoalCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", category.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            if let entity = entities.first {
                entity.name = category.name
                save()
            }
        } catch {
            print("❌ Failed to update category: \(error)")
        }
    }
    
    func deleteCategory(_ category: GoalCategory) {
        let request: NSFetchRequest<GoalCategoryEntity> = GoalCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", category.id.uuidString)
        
        do {
            let entities = try context.fetch(request)
            entities.forEach(context.delete)
            save()
        } catch {
            print("❌ Failed to delete category: \(error)")
        }
    }
}

// MARK: - Extensions for WeightLogEntry
extension WeightLogEntry {
    init(id: String, timestamp: Date, weight: Double, unit: WeightUnit, userId: String) {
        self.id = id
        self.timestamp = timestamp
        self.weight = weight
        self.unit = unit
        self.userId = userId
    }
}

// MARK: - Extensions for WorkoutLogEntry
extension WorkoutLogEntry {
    init(id: String, date: Date, name: String, userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = createdAt
    }
}

// MARK: - Extensions for FoodLogEntry
extension FoodLogEntry {
    init(id: String, date: Date, name: String, userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = createdAt
    }
} 