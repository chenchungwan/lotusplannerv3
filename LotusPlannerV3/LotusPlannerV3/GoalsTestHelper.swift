import Foundation

// MARK: - Goals Test Helper
// This file contains helper functions to test the goals data model
// Remove this file in production

extension GoalsManager {
    
    /// Create sample data for testing
    func createSampleData() {
        // Clear existing data
        categories.removeAll()
        goals.removeAll()
        
        // Create sample categories
        let sampleCategories = [
            GoalCategoryData(title: "Health & Fitness", displayPosition: 0),
            GoalCategoryData(title: "Career", displayPosition: 1),
            GoalCategoryData(title: "Personal Growth", displayPosition: 2),
            GoalCategoryData(title: "Relationships", displayPosition: 3),
            GoalCategoryData(title: "Finance", displayPosition: 4),
            GoalCategoryData(title: "Hobbies", displayPosition: 5)
        ]
        
        for category in sampleCategories {
            addCategory(title: category.title, displayPosition: category.displayPosition)
        }
        
        // Create sample goals
        let healthCategoryId = categories.first { $0.title == "Health & Fitness" }?.id ?? UUID()
        let careerCategoryId = categories.first { $0.title == "Career" }?.id ?? UUID()
        let personalCategoryId = categories.first { $0.title == "Personal Growth" }?.id ?? UUID()
        
        let sampleGoals = [
            GoalData(
                title: "Run 5K",
                description: "Complete a 5K run without stopping",
                successMetric: "Run 5 kilometers in under 30 minutes",
                categoryId: healthCategoryId,
                targetTimeframe: .month,
                dueDate: GoalData.calculateDueDate(for: .month)
            ),
            GoalData(
                title: "Learn SwiftUI",
                description: "Master SwiftUI development",
                successMetric: "Build 3 complete apps using SwiftUI",
                categoryId: careerCategoryId,
                targetTimeframe: .year,
                dueDate: GoalData.calculateDueDate(for: .year)
            ),
            GoalData(
                title: "Read 12 Books",
                description: "Read one book per month",
                successMetric: "Complete 12 books by end of year",
                categoryId: personalCategoryId,
                targetTimeframe: .year,
                dueDate: GoalData.calculateDueDate(for: .year)
            ),
            GoalData(
                title: "Meditate Daily",
                description: "Establish daily meditation practice",
                successMetric: "Meditate for 10+ minutes daily for 30 days",
                categoryId: personalCategoryId,
                targetTimeframe: .month,
                dueDate: GoalData.calculateDueDate(for: .month)
            )
        ]
        
        for goal in sampleGoals {
            addGoal(goal)
        }
    }
    
    /// Print current data for debugging
    func printCurrentData() {
        print("=== GOALS DATA ===")
        print("Categories (\(categories.count)):")
        for category in categories.sorted(by: { $0.displayPosition < $1.displayPosition }) {
            print("  [\(category.displayPosition)] \(category.title)")
        }
        
        print("\nGoals (\(goals.count)):")
        for goal in goals {
            let categoryName = getCategoryById(goal.categoryId)?.title ?? "Unknown"
            let status = goal.isCompleted ? "✅" : "⭕"
            let timeframe = goal.targetTimeframe.displayName
            print("  \(status) \(goal.title) (\(categoryName), \(timeframe))")
            if !goal.description.isEmpty {
                print("    Description: \(goal.description)")
            }
            if !goal.successMetric.isEmpty {
                print("    Success Metric: \(goal.successMetric)")
            }
            print("    Due: \(goal.dueDate.formatted(date: .abbreviated, time: .omitted))")
            if goal.isOverdue {
                print("    ⚠️ OVERDUE")
            } else if goal.daysRemaining > 0 {
                print("    Days remaining: \(goal.daysRemaining)")
            }
        }
        print("==================")
    }
    
    /// Test data model functionality
    func runTests() {
        print("🧪 Running Goals Data Model Tests...")
        
        // Test 1: Create sample data
        print("\n1. Creating sample data...")
        createSampleData()
        printCurrentData()
        
        // Test 2: Update a goal
        print("\n2. Updating a goal...")
        if let firstGoal = goals.first {
            var updatedGoal = firstGoal
            updatedGoal.isCompleted = true
            updateGoal(updatedGoal)
        }
        
        // Test 3: Add a new goal
        print("\n3. Adding a new goal...")
        if let healthCategory = categories.first(where: { $0.title == "Health & Fitness" }) {
            let newGoal = GoalData(
                title: "Drink 8 Glasses of Water Daily",
                description: "Stay hydrated throughout the day",
                successMetric: "Drink 8 glasses of water for 7 consecutive days",
                categoryId: healthCategory.id,
                targetTimeframe: .week,
                dueDate: GoalData.calculateDueDate(for: .week)
            )
            addGoal(newGoal)
        }
        
        // Test 4: Reorder categories
        print("\n4. Reordering categories...")
        categories = categories.shuffled()
        reorderCategories()
        
        printCurrentData()
        
        print("\n✅ Tests completed!")
    }
}

// MARK: - Convenience Extensions for Testing
extension GoalData {
    static func createSampleGoal(
        title: String,
        description: String = "",
        successMetric: String = "",
        categoryId: UUID,
        timeframe: GoalTimeframe = .month
    ) -> GoalData {
        return GoalData(
            title: title,
            description: description,
            successMetric: successMetric,
            categoryId: categoryId,
            targetTimeframe: timeframe,
            dueDate: calculateDueDate(for: timeframe)
        )
    }
}

extension GoalCategoryData {
    static func createSampleCategory(
        title: String,
        position: Int
    ) -> GoalCategoryData {
        return GoalCategoryData(
            title: title,
            displayPosition: position
        )
    }
}
