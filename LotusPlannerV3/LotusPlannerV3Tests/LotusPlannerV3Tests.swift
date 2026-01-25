//
//  LotusPlannerV3Tests.swift
//  LotusPlannerV3Tests
//
//  Working regression test suite for LotusPlannerV3
//

import XCTest
import CoreData
import SwiftUI
@testable import LotusPlannerV3

final class LotusPlannerV3Tests: XCTestCase {

    // MARK: - Test Infrastructure

    var persistenceController: PersistenceController!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Use in-memory store for testing
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.container.viewContext
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        testContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Core Data Tests

    func testPersistenceControllerInitialization() throws {
        XCTAssertNotNil(persistenceController, "PersistenceController should initialize")
        XCTAssertNotNil(persistenceController.container, "NSPersistentCloudKitContainer should exist")
        XCTAssertNotNil(testContext, "ViewContext should be accessible")
    }

    func testWeightLogCreation() throws {
        let weightLog = WeightLog(context: testContext)
        weightLog.id = "test-weight-1"
        weightLog.date = Date()
        weightLog.weight = 150.5
        weightLog.unit = "lbs"

        try testContext.save()

        let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one weight log")
        XCTAssertEqual(results.first?.weight, 150.5, "Weight should be saved correctly")
        XCTAssertEqual(results.first?.unit, "lbs", "Unit should be saved")
    }

    func testWorkoutLogCreation() throws {
        let workoutLog = WorkoutLog(context: testContext)
        workoutLog.id = "test-workout-1"
        workoutLog.date = Date()
        workoutLog.name = "Morning Run"

        try testContext.save()

        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one workout log")
        XCTAssertEqual(results.first?.name, "Morning Run", "Workout name should be saved")
    }

    func testFoodLogCreation() throws {
        let foodLog = FoodLog(context: testContext)
        foodLog.id = "test-food-1"
        foodLog.date = Date()
        foodLog.name = "Breakfast"

        try testContext.save()

        let fetchRequest: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one food log")
        XCTAssertEqual(results.first?.name, "Breakfast", "Food name should be saved")
    }

    func testTaskTimeWindowCreation() throws {
        let taskWindow = TaskTimeWindow(context: testContext)
        taskWindow.id = "test-window-1"
        taskWindow.taskId = "test-task-123"
        taskWindow.startTime = Date()
        taskWindow.endTime = Date().addingTimeInterval(3600) // 1 hour later
        taskWindow.isAllDay = false

        try testContext.save()

        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one task time window")
        XCTAssertEqual(results.first?.taskId, "test-task-123", "Task ID should be saved")
        XCTAssertFalse(results.first?.isAllDay ?? true, "Should not be all day")
    }

    func testCustomLogItemCreation() throws {
        let logItem = CustomLogItem(context: testContext)
        logItem.id = "test-item-1"
        logItem.title = "Test Item"
        logItem.isEnabled = true
        logItem.displayOrder = 0

        try testContext.save()

        let fetchRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one custom log item")
        XCTAssertEqual(results.first?.title, "Test Item", "Title should be saved")
        XCTAssertTrue(results.first?.isEnabled ?? false, "Should be enabled")
    }

    func testCustomLogEntryCreation() throws {
        let logEntry = CustomLogEntry(context: testContext)
        logEntry.id = "test-entry-1"
        logEntry.itemId = "test-item-1"
        logEntry.date = Date()
        logEntry.isCompleted = true

        try testContext.save()

        let fetchRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one custom log entry")
        XCTAssertTrue(results.first?.isCompleted ?? false, "Should be completed")
    }

    func testGoalCreation() throws {
        let goal = Goal(context: testContext)
        goal.id = "test-goal-1"
        goal.title = "Test Goal"
        goal.goalDescription = "Description"
        goal.categoryId = "test-category-1"
        goal.isCompleted = false

        try testContext.save()

        let fetchRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one goal")
        XCTAssertEqual(results.first?.title, "Test Goal", "Title should be saved")
        XCTAssertFalse(results.first?.isCompleted ?? true, "Should not be completed")
    }

    func testGoalCategoryCreation() throws {
        let category = GoalCategory(context: testContext)
        category.id = "test-category-1"
        category.title = "Test Category"
        category.displayPosition = 0

        try testContext.save()

        let fetchRequest: NSFetchRequest<GoalCategory> = GoalCategory.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one goal category")
        XCTAssertEqual(results.first?.title, "Test Category", "Title should be saved")
    }

    func testSleepLogCreation() throws {
        let sleepLog = SleepLog(context: testContext)
        sleepLog.id = "test-sleep-1"
        sleepLog.date = Date()
        sleepLog.bedTime = Date()
        sleepLog.wakeUpTime = Date().addingTimeInterval(28800) // 8 hours later

        try testContext.save()

        let fetchRequest: NSFetchRequest<SleepLog> = SleepLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one sleep log")
        XCTAssertNotNil(results.first?.bedTime, "Bed time should be saved")
        XCTAssertNotNil(results.first?.wakeUpTime, "Wake up time should be saved")
    }

    func testWaterLogCreation() throws {
        let waterLog = WaterLog(context: testContext)
        waterLog.id = "test-water-1"
        waterLog.date = Date()
        waterLog.cupsConsumed = 8

        try testContext.save()

        let fetchRequest: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have one water log")
        XCTAssertEqual(results.first?.cupsConsumed, 8, "Cups consumed should be saved")
    }

    // MARK: - Manager Tests

    func testGoalsManagerMaxCategories() {
        XCTAssertEqual(GoalsManager.maxCategories, 6, "Should have max 6 categories")
    }

    // MARK: - Calendar Utility Tests

    func testCalendarMondayFirst() {
        let calendar = Calendar.mondayFirst
        XCTAssertEqual(calendar.firstWeekday, 2, "Monday should be first day of week (2)")
    }

    // MARK: - Priority Tests

    func testTaskPriorityValues() {
        let allValues = TaskPriorityData.allValues
        XCTAssertEqual(allValues.count, 5, "Should have 5 priority levels")
        XCTAssertTrue(allValues.contains("P0"), "Should include P0")
        XCTAssertTrue(allValues.contains("P4"), "Should include P4")
    }

    func testTaskPriorityColors() {
        let p0 = TaskPriorityData(value: "P0")
        let p1 = TaskPriorityData(value: "P1")
        let p2 = TaskPriorityData(value: "P2")
        let p3 = TaskPriorityData(value: "P3")
        let p4 = TaskPriorityData(value: "P4")

        XCTAssertEqual(p0.color, .red, "P0 should be red")
        XCTAssertEqual(p1.color, .orange, "P1 should be orange")
        XCTAssertEqual(p2.color, .yellow, "P2 should be yellow")
        XCTAssertEqual(p3.color, .green, "P3 should be green")
        XCTAssertEqual(p4.color, .blue, "P4 should be blue")
    }

    func testTaskPriorityEncoding() {
        let priority = TaskPriorityData(value: "P2")
        XCTAssertEqual(priority.encodedTag, "[PRIORITY:P2]", "Should encode correctly")
    }

    func testTaskPriorityParsing() {
        let notes = "[PRIORITY:P1]\nSome task notes"
        let parsed = TaskPriorityData.parse(from: notes)

        XCTAssertNotNil(parsed, "Should parse priority")
        XCTAssertEqual(parsed?.value, "P1", "Should extract P1")
    }

    func testTaskPriorityRemoveTag() {
        let notes = "[PRIORITY:P3]\nTask description"
        let cleaned = TaskPriorityData.removeTag(from: notes)

        XCTAssertEqual(cleaned, "Task description", "Should remove priority tag")
    }

    func testTaskPrioritySortOrder() {
        let p0 = TaskPriorityData(value: "P0")
        let p4 = TaskPriorityData(value: "P4")

        XCTAssertLessThan(p0.sortOrder, p4.sortOrder, "P0 should sort before P4")
    }

    // MARK: - Edge Case Tests

    func testNilDateHandling() throws {
        let weightLog = WeightLog(context: testContext)
        weightLog.id = "test-nil-date"
        weightLog.date = nil
        weightLog.weight = 150.0

        // Should not crash when saving with nil date
        XCTAssertNoThrow(try testContext.save())
    }

    func testInvalidWeightValues() throws {
        let weightLog = WeightLog(context: testContext)
        weightLog.id = "test-negative"
        weightLog.date = Date()
        weightLog.weight = -1.0 // Negative weight

        try testContext.save()

        let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.first?.weight, -1.0, "Should save negative weight (validation in UI)")
    }

    // MARK: - Performance Tests

    func testCoreDataBatchInsertPerformance() throws {
        measure {
            let context = persistenceController.container.newBackgroundContext()
            context.performAndWait {
                for i in 0..<100 {
                    let weightLog = WeightLog(context: context)
                    weightLog.id = "perf-test-\(i)"
                    weightLog.date = Date().addingTimeInterval(TimeInterval(i * 86400))
                    weightLog.weight = 150.0 + Double(i)
                }
                try? context.save()
            }
        }
    }

    func testCoreDataFetchPerformance() throws {
        // Setup: Create test data
        for i in 0..<100 {
            let weightLog = WeightLog(context: testContext)
            weightLog.id = "fetch-test-\(i)"
            weightLog.date = Date().addingTimeInterval(TimeInterval(i * 86400))
            weightLog.weight = 150.0 + Double(i)
        }
        try testContext.save()

        // Measure fetch performance
        measure {
            let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
            _ = try? testContext.fetch(fetchRequest)
        }
    }
}
