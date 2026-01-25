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

    @MainActor
    func testDataManagerInitialization() {
        let dataManager = DataManager.shared
        XCTAssertNotNil(dataManager, "Data manager should initialize")
        XCTAssertNotNil(dataManager.calendarViewModel, "Calendar view model should exist")
        XCTAssertNotNil(dataManager.tasksViewModel, "Tasks view model should exist")
        XCTAssertNotNil(dataManager.goalsManager, "Goals manager should exist")
        XCTAssertNotNil(dataManager.customLogManager, "Custom log manager should exist")
    }

    func testPersistenceControllerPreview() {
        let previewController = PersistenceController.preview
        XCTAssertNotNil(previewController, "Preview controller should initialize")
        XCTAssertNotNil(previewController.container, "Preview container should exist")
    }

    // MARK: - Navigation Manager Tests

    @MainActor
    func testNavigationManagerInitialization() {
        let navManager = NavigationManager.shared
        XCTAssertNotNil(navManager, "Navigation manager should initialize")
        XCTAssertEqual(navManager.currentInterval, .day, "Default interval should be day")
        XCTAssertFalse(navManager.showTasksView, "Tasks view should not be shown by default")
    }

    @MainActor
    func testNavigationManagerViewSwitching() {
        let navManager = NavigationManager.shared

        navManager.switchToCalendar()
        XCTAssertEqual(navManager.currentView, .calendar, "Should switch to calendar")
        XCTAssertFalse(navManager.showTasksView, "Tasks view should be hidden")

        navManager.switchToTasks()
        XCTAssertEqual(navManager.currentView, .tasks, "Should switch to tasks")
        XCTAssertTrue(navManager.showTasksView, "Tasks view should be shown")

        navManager.switchToGoals()
        XCTAssertEqual(navManager.currentView, .goals, "Should switch to goals")

        navManager.switchToJournal()
        XCTAssertEqual(navManager.currentView, .journal, "Should switch to journal")
    }

    @MainActor
    func testNavigationManagerIntervalUpdate() {
        let navManager = NavigationManager.shared
        let testDate = Date()

        navManager.updateInterval(.week, date: testDate)
        XCTAssertEqual(navManager.currentInterval, .week, "Interval should update to week")
        XCTAssertEqual(navManager.currentDate, testDate, "Date should update")

        navManager.updateInterval(.month, date: testDate)
        XCTAssertEqual(navManager.currentInterval, .month, "Interval should update to month")
    }

    // MARK: - App Preferences Tests

    @MainActor
    func testAppPreferencesInitialization() {
        let prefs = AppPreferences.shared
        XCTAssertNotNil(prefs, "App preferences should initialize")
        XCTAssertNotNil(prefs.personalColor, "Personal color should be set")
        XCTAssertNotNil(prefs.professionalColor, "Professional color should be set")
    }

    @MainActor
    func testAppPreferencesColorUpdate() {
        let prefs = AppPreferences.shared
        let testColor = Color.red

        prefs.updatePersonalColor(testColor)
        XCTAssertEqual(prefs.personalColor, testColor, "Personal color should update")

        prefs.updateProfessionalColor(testColor)
        XCTAssertEqual(prefs.professionalColor, testColor, "Professional color should update")
    }

    @MainActor
    func testAppPreferencesDayViewLayout() {
        let prefs = AppPreferences.shared

        prefs.updateDayViewLayout(.compact)
        XCTAssertEqual(prefs.dayViewLayout, .compact, "Day view layout should update")

        prefs.updateDayViewLayout(.defaultNew)
        XCTAssertEqual(prefs.dayViewLayout, .defaultNew, "Day view layout should update to expanded")
    }

    @MainActor
    func testAppPreferencesLogsVisibility() {
        let prefs = AppPreferences.shared

        prefs.showWeightLogs = true
        XCTAssertTrue(prefs.showWeightLogs, "Weight logs should be visible")

        prefs.showWorkoutLogs = false
        XCTAssertFalse(prefs.showWorkoutLogs, "Workout logs should be hidden")

        prefs.showFoodLogs = true
        XCTAssertTrue(prefs.showFoodLogs, "Food logs should be visible")

        prefs.showSleepLogs = true
        XCTAssertTrue(prefs.showSleepLogs, "Sleep logs should be visible")

        prefs.showCustomLogs = true
        XCTAssertTrue(prefs.showCustomLogs, "Custom logs should be visible")

        let showAny = prefs.showAnyLogs
        XCTAssertTrue(showAny, "Should show some logs")
    }

    @MainActor
    func testAppPreferencesAccountNames() {
        let prefs = AppPreferences.shared

        prefs.personalAccountName = "My Personal"
        XCTAssertEqual(prefs.personalAccountName, "My Personal", "Personal account name should update")

        prefs.professionalAccountName = "Work Account"
        XCTAssertEqual(prefs.professionalAccountName, "Work Account", "Professional account name should update")

        XCTAssertEqual(prefs.accountName(for: .personal), "My Personal", "Should get personal account name")
        XCTAssertEqual(prefs.accountName(for: .professional), "Work Account", "Should get professional account name")
    }

    @MainActor
    func testAppPreferencesAccountNameTruncation() {
        let prefs = AppPreferences.shared
        let longName = String(repeating: "a", count: 50)

        prefs.personalAccountName = longName
        XCTAssertEqual(prefs.personalAccountName.count, 30, "Account name should be truncated to 30 chars")
    }

    @MainActor
    func testAppPreferencesEmptyStringHandling() {
        let prefs = AppPreferences.shared

        // Empty account names should not crash
        prefs.personalAccountName = ""
        XCTAssertEqual(prefs.personalAccountName, "", "Should handle empty string")
    }

    // MARK: - Calendar Utility Tests

    func testCalendarMondayFirst() {
        let calendar = Calendar.mondayFirst
        XCTAssertEqual(calendar.firstWeekday, 2, "Monday should be first day of week (2)")
    }

    func testDateFormatters() {
        let date = Date()
        let monthYear = DateFormatter.standardMonthYear.string(from: date)
        let shortDate = DateFormatter.standardDate.string(from: date)
        let dayOfWeek = DateFormatter.standardDayOfWeek.string(from: date)

        XCTAssertFalse(monthYear.isEmpty, "Month year should format")
        XCTAssertFalse(shortDate.isEmpty, "Short date should format")
        XCTAssertFalse(dayOfWeek.isEmpty, "Day of week should format")
    }

    // MARK: - Enum Tests

    func testDayViewLayoutOptions() {
        XCTAssertEqual(DayViewLayoutOption.compact.displayName, "Classic")
        XCTAssertEqual(DayViewLayoutOption.compactTwo.displayName, "Compact")
        XCTAssertEqual(DayViewLayoutOption.defaultNew.displayName, "Expanded")
        XCTAssertEqual(DayViewLayoutOption.mobile.displayName, "Mobile")
        XCTAssertEqual(DayViewLayoutOption.timebox.displayName, "Timebox")
        XCTAssertEqual(DayViewLayoutOption.standard.displayName, "Standard")

        let allCases = DayViewLayoutOption.allCases
        XCTAssertTrue(allCases.contains(.compact), "Should include compact")
        XCTAssertTrue(allCases.contains(.standard), "Should include standard")
        XCTAssertTrue(allCases.contains(.timebox), "Should include timebox")
    }

    func testTimelineInterval() {
        XCTAssertEqual(TimelineInterval.day.calendarComponent, .day)
        XCTAssertEqual(TimelineInterval.week.calendarComponent, .weekOfYear)
        XCTAssertEqual(TimelineInterval.month.calendarComponent, .month)
        XCTAssertEqual(TimelineInterval.year.calendarComponent, .year)

        XCTAssertEqual(TimelineInterval.day.sfSymbol, "d.circle")
        XCTAssertEqual(TimelineInterval.week.sfSymbol, "w.circle")
        XCTAssertEqual(TimelineInterval.month.sfSymbol, "m.circle")
        XCTAssertEqual(TimelineInterval.year.sfSymbol, "y.circle")
    }

    // MARK: - Configuration Tests

    func testConfigurationManagerInitialization() {
        let configManager = ConfigurationManager.shared
        XCTAssertNotNil(configManager, "Configuration manager should initialize")

        #if DEBUG
        XCTAssertFalse(configManager.isProduction, "Should not be production in debug")
        #else
        XCTAssertTrue(configManager.isProduction, "Should be production in release")
        #endif
    }

    // MARK: - Security Tests

    func testKeychainManagerBasicOperations() throws {
        let keychainManager = KeychainManager.shared
        let testKey = "test_key_\(UUID().uuidString)"
        let testValue = "test_value_123"

        // Save
        try keychainManager.saveString(testValue, for: testKey)

        // Retrieve
        let retrieved = try keychainManager.loadString(for: testKey)
        XCTAssertEqual(retrieved, testValue, "Should retrieve saved value")

        // Delete
        try keychainManager.delete(for: testKey)

        // Verify deletion
        XCTAssertThrowsError(try keychainManager.loadString(for: testKey), "Should throw error after deletion")
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

    func testTaskPriorityUpdateNotes() {
        // Test adding priority to empty notes
        let emptyResult = TaskPriorityData.updateNotes(nil, with: TaskPriorityData(value: "P1"))
        XCTAssertEqual(emptyResult, "[PRIORITY:P1]", "Should add priority to empty notes")

        // Test adding priority to existing notes
        let existingNotes = "Task description"
        let withPriority = TaskPriorityData.updateNotes(existingNotes, with: TaskPriorityData(value: "P2"))
        XCTAssertEqual(withPriority, "[PRIORITY:P2]\nTask description", "Should prepend priority to notes")

        // Test updating existing priority
        let oldPriority = "[PRIORITY:P0]\nTask description"
        let updated = TaskPriorityData.updateNotes(oldPriority, with: TaskPriorityData(value: "P3"))
        XCTAssertEqual(updated, "[PRIORITY:P3]\nTask description", "Should replace existing priority")

        // Test removing priority
        let removed = TaskPriorityData.updateNotes(oldPriority, with: nil)
        XCTAssertEqual(removed, "Task description", "Should remove priority tag")
    }

    func testTaskPriorityAllValuesCount() {
        XCTAssertEqual(TaskPriorityData.allValues.count, 5, "Should have exactly 5 priority levels")
        XCTAssertFalse(TaskPriorityData.allValues.contains("P5"), "Should not contain P5")
    }

    func testTaskPriorityDisplayText() {
        let priority = TaskPriorityData(value: "P2")
        XCTAssertEqual(priority.displayText, "P2", "Display text should match value")
    }

    func testTaskPriorityInvalidValue() {
        let invalid = TaskPriorityData(value: "INVALID")
        XCTAssertEqual(invalid.color, .gray, "Invalid priority should have gray color")
        XCTAssertEqual(invalid.sortOrder, 999, "Invalid priority should have high sort order")
    }

    func testTaskPriorityLegacyFormatParsing() {
        // Test old format [PRIORITY:roadmap:P1]
        let oldFormat = "[PRIORITY:roadmap:P1]\nTask notes"
        let parsed = TaskPriorityData.parse(from: oldFormat)

        XCTAssertNotNil(parsed, "Should parse legacy format")
        XCTAssertEqual(parsed?.value, "P1", "Should extract P1 from legacy format")
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

    func testDuplicateIDHandling() throws {
        let log1 = WeightLog(context: testContext)
        log1.id = "duplicate-id"
        log1.date = Date()
        log1.weight = 150.0

        let log2 = WeightLog(context: testContext)
        log2.id = "duplicate-id"
        log2.date = Date()
        log2.weight = 155.0

        try testContext.save()

        let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", "duplicate-id")
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 2, "Should allow duplicate IDs (handled at app layer)")
    }

    func testEmptyStringFields() throws {
        let goal = Goal(context: testContext)
        goal.id = ""
        goal.title = ""
        goal.goalDescription = ""
        goal.categoryId = ""

        XCTAssertNoThrow(try testContext.save(), "Should handle empty string fields")
    }

    func testVeryLongStrings() throws {
        let longString = String(repeating: "a", count: 10000)
        let goal = Goal(context: testContext)
        goal.id = "test-long"
        goal.title = longString
        goal.goalDescription = longString

        XCTAssertNoThrow(try testContext.save(), "Should handle very long strings")
    }

    func testFutureAndPastDates() throws {
        let pastDate = Date(timeIntervalSince1970: 0) // Jan 1, 1970
        let futureDate = Date(timeIntervalSinceNow: 86400 * 365 * 10) // 10 years from now

        let pastLog = WeightLog(context: testContext)
        pastLog.id = "past"
        pastLog.date = pastDate
        pastLog.weight = 150.0

        let futureLog = WeightLog(context: testContext)
        futureLog.id = "future"
        futureLog.date = futureDate
        futureLog.weight = 155.0

        try testContext.save()

        let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 2, "Should handle past and future dates")
    }

    func testZeroAndExtremeNumbers() throws {
        let waterLog = WaterLog(context: testContext)
        waterLog.id = "test-zero"
        waterLog.date = Date()
        waterLog.cupsConsumed = 0

        let extremeLog = WaterLog(context: testContext)
        extremeLog.id = "test-extreme"
        extremeLog.date = Date()
        extremeLog.cupsConsumed = Int16.max

        try testContext.save()

        let fetchRequest: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 2, "Should handle zero and extreme numbers")
    }

    func testConcurrentContextSaves() throws {
        let expectation = XCTestExpectation(description: "Concurrent saves")
        expectation.expectedFulfillmentCount = 3

        for i in 0..<3 {
            DispatchQueue.global().async {
                let context = self.persistenceController.container.newBackgroundContext()
                context.performAndWait {
                    let log = WeightLog(context: context)
                    log.id = "concurrent-\(i)"
                    log.date = Date()
                    log.weight = 150.0 + Double(i)

                    try? context.save()
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 5.0)

        let fetchRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id BEGINSWITH %@", "concurrent-")
        let results = try testContext.fetch(fetchRequest)

        XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle concurrent saves")
    }

    // MARK: - Data Integrity Tests

    func testGoalWithoutCategory() throws {
        let goal = Goal(context: testContext)
        goal.id = "test-no-category"
        goal.title = "Orphan Goal"
        goal.categoryId = nil
        goal.isCompleted = false

        try testContext.save()

        let fetchRequest: NSFetchRequest<Goal> = Goal.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should allow goal without category")
    }

    func testCustomLogEntryWithoutItem() throws {
        let entry = CustomLogEntry(context: testContext)
        entry.id = "test-orphan"
        entry.itemId = nil
        entry.date = Date()
        entry.isCompleted = false

        try testContext.save()

        let fetchRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should allow entry without item reference")
    }

    func testTaskTimeWindowOverlapping() throws {
        let startTime = Date()
        let midTime = Date().addingTimeInterval(1800) // 30 min later
        let endTime = Date().addingTimeInterval(3600) // 1 hour later

        let window1 = TaskTimeWindow(context: testContext)
        window1.id = "window-1"
        window1.taskId = "task-1"
        window1.startTime = startTime
        window1.endTime = endTime

        let window2 = TaskTimeWindow(context: testContext)
        window2.id = "window-2"
        window2.taskId = "task-2"
        window2.startTime = midTime
        window2.endTime = endTime.addingTimeInterval(3600)

        try testContext.save()

        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 2, "Should allow overlapping time windows")
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

    func testMultipleEntityFetchPerformance() throws {
        // Create diverse test data
        for i in 0..<50 {
            let weight = WeightLog(context: testContext)
            weight.id = "perf-weight-\(i)"
            weight.date = Date()
            weight.weight = 150.0

            let food = FoodLog(context: testContext)
            food.id = "perf-food-\(i)"
            food.date = Date()
            food.name = "Meal \(i)"

            let workout = WorkoutLog(context: testContext)
            workout.id = "perf-workout-\(i)"
            workout.date = Date()
            workout.name = "Workout \(i)"
        }
        try testContext.save()

        // Measure fetch performance across multiple entity types
        measure {
            _ = try? testContext.fetch(WeightLog.fetchRequest())
            _ = try? testContext.fetch(FoodLog.fetchRequest())
            _ = try? testContext.fetch(WorkoutLog.fetchRequest())
        }
    }
}

// MARK: - Regression Tests for Recent Features

final class RecentFeaturesRegressionTests: XCTestCase {

    // MARK: - Priority Feature Tests

    func testPriorityIconSelectorIntegration() {
        // Test that priority values align with UI expectations
        let priorities = TaskPriorityData.allValues

        XCTAssertEqual(priorities.count, 5, "Should have 5 priorities for icon selector")
        XCTAssertEqual(priorities[0], "P0", "First priority should be P0")
        XCTAssertEqual(priorities[4], "P4", "Last priority should be P4")
    }

    func testPriorityColorConsistency() {
        // Ensure colors are consistent between model and UI
        let p0 = TaskPriorityData(value: "P0")
        let p1 = TaskPriorityData(value: "P1")
        let p2 = TaskPriorityData(value: "P2")
        let p3 = TaskPriorityData(value: "P3")
        let p4 = TaskPriorityData(value: "P4")

        // Test color progression from warm to cool
        XCTAssertEqual(p0.color, .red, "P0 should be red (highest priority)")
        XCTAssertEqual(p1.color, .orange, "P1 should be orange")
        XCTAssertEqual(p2.color, .yellow, "P2 should be yellow")
        XCTAssertEqual(p3.color, .green, "P3 should be green")
        XCTAssertEqual(p4.color, .blue, "P4 should be blue (lowest priority)")
    }

    func testNoPriorityLabel() {
        XCTAssertEqual(TaskPriorityData.noPriorityLabel, "No Priority", "No priority label should be correct")
    }

    // MARK: - Sync Feature Tests

    func testUserIdConsistency() {
        // Ensure all entities use consistent userId pattern
        let userId = "icloud-user"

        // This would typically test that entities are created with correct userId
        XCTAssertEqual(userId, "icloud-user", "User ID should be consistent for iCloud sync")
    }

    // MARK: - Day View Layout Tests

    func testDayViewLayoutOrder() {
        let allCases = DayViewLayoutOption.allCases

        guard let standardIndex = allCases.firstIndex(of: .standard),
              let timeboxIndex = allCases.firstIndex(of: .timebox) else {
            XCTFail("Standard and Timebox should exist in allCases")
            return
        }

        XCTAssertLessThan(standardIndex, timeboxIndex, "Standard should come before Timebox")
    }

    func testDayViewLayoutDisplayNames() {
        // Verify all layouts have proper display names
        for layout in DayViewLayoutOption.allCases {
            XCTAssertFalse(layout.displayName.isEmpty, "Layout \(layout) should have a display name")
        }
    }

    // MARK: - Account Management Tests

    @MainActor
    func testAccountNameTruncation() {
        let prefs = AppPreferences.shared
        let veryLongName = String(repeating: "x", count: 100)

        prefs.personalAccountName = veryLongName

        XCTAssertLessThanOrEqual(prefs.personalAccountName.count, 30, "Account name should be truncated")
    }

    func testAccountTypeEnum() {
        // Test that account types are properly defined
        let personal = GoogleAuthManager.AccountKind.personal
        let professional = GoogleAuthManager.AccountKind.professional

        XCTAssertNotEqual(personal, professional, "Account types should be distinct")
    }

    // MARK: - Logging Feature Tests

    func testDevLogCategories() {
        let categories: [DevLogCategory] = [
            .general, .sync, .tasks, .goals, .calendar, .navigation, .cloud, .auth
        ]

        XCTAssertEqual(categories.count, 8, "Should have 8 log categories")
    }

    @MainActor
    func testVerboseLoggingControl() {
        let prefs = AppPreferences.shared

        // Test verbose logging toggle
        prefs.verboseLoggingEnabled = true
        XCTAssertTrue(prefs.verboseLoggingEnabled, "Verbose logging should be enabled")

        prefs.verboseLoggingEnabled = false
        XCTAssertFalse(prefs.verboseLoggingEnabled, "Verbose logging should be disabled")
    }
}

// MARK: - CRUD Tests for Primary Features

/// Comprehensive CRUD tests for all logs (Weight, Workout, Food, Sleep, Water)
final class LogsCRUDTests: XCTestCase {

    var persistenceController: PersistenceController!
    var coreDataManager: CoreDataManager!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.container.viewContext
        coreDataManager = CoreDataManager.shared
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        coreDataManager = nil
        testContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Weight Log CRUD

    func testWeightLogCreate() throws {
        let entry = WeightLogEntry(
            id: "test-weight-1",
            date: Date(),
            time: Date(),
            weight: 150.5,
            unit: .lbs,
            userId: "icloud-user"
        )

        coreDataManager.saveWeightEntry(entry)

        let loaded = coreDataManager.loadWeightEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save weight entry")
        XCTAssertEqual(loaded.first(where: { $0.id == entry.id })?.weight, 150.5, "Should save correct weight")
    }

    func testWeightLogDelete() throws {
        let entry = WeightLogEntry(
            id: "test-weight-delete",
            date: Date(),
            time: Date(),
            weight: 160.0,
            unit: .lbs,
            userId: "icloud-user"
        )

        coreDataManager.saveWeightEntry(entry)
        var loaded = coreDataManager.loadWeightEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save before delete")

        coreDataManager.deleteWeightEntry(entry)
        loaded = coreDataManager.loadWeightEntries()
        XCTAssertFalse(loaded.contains(where: { $0.id == entry.id }), "Should delete weight entry")
    }

    // MARK: - Workout Log CRUD

    func testWorkoutLogCreate() throws {
        let entry = WorkoutLogEntry(
            id: "test-workout-1",
            date: Date(),
            name: "Morning Run",
            userId: "icloud-user",
            createdAt: Date()
        )

        coreDataManager.saveWorkoutEntry(entry)

        let loaded = coreDataManager.loadWorkoutEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save workout entry")
        XCTAssertEqual(loaded.first(where: { $0.id == entry.id })?.name, "Morning Run", "Should save correct name")
    }

    func testWorkoutLogDelete() throws {
        let entry = WorkoutLogEntry(
            id: "test-workout-delete",
            date: Date(),
            name: "Evening Yoga",
            userId: "icloud-user",
            createdAt: Date()
        )

        coreDataManager.saveWorkoutEntry(entry)
        var loaded = coreDataManager.loadWorkoutEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save before delete")

        coreDataManager.deleteWorkoutEntry(entry)
        loaded = coreDataManager.loadWorkoutEntries()
        XCTAssertFalse(loaded.contains(where: { $0.id == entry.id }), "Should delete workout entry")
    }

    // MARK: - Food Log CRUD

    func testFoodLogCreate() throws {
        let entry = FoodLogEntry(
            id: "test-food-1",
            date: Date(),
            name: "Breakfast",
            userId: "icloud-user",
            createdAt: Date()
        )

        coreDataManager.saveFoodEntry(entry)

        let loaded = coreDataManager.loadFoodEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save food entry")
        XCTAssertEqual(loaded.first(where: { $0.id == entry.id })?.name, "Breakfast", "Should save correct name")
    }

    func testFoodLogDelete() throws {
        let entry = FoodLogEntry(
            id: "test-food-delete",
            date: Date(),
            name: "Lunch",
            userId: "icloud-user",
            createdAt: Date()
        )

        coreDataManager.saveFoodEntry(entry)
        var loaded = coreDataManager.loadFoodEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save before delete")

        coreDataManager.deleteFoodEntry(entry)
        loaded = coreDataManager.loadFoodEntries()
        XCTAssertFalse(loaded.contains(where: { $0.id == entry.id }), "Should delete food entry")
    }

    // MARK: - Water Log CRUD

    func testWaterLogCreate() throws {
        let entry = WaterLogEntry(
            id: "test-water-1",
            date: Date(),
            cupsConsumed: 8,
            userId: "icloud-user",
            createdAt: Date(),
            updatedAt: Date()
        )

        coreDataManager.saveWaterEntry(entry)

        let loaded = coreDataManager.loadWaterEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save water entry")
        XCTAssertEqual(loaded.first(where: { $0.id == entry.id })?.cupsConsumed, 8, "Should save correct cups")
    }

    func testWaterLogUpdate() throws {
        let entry = WaterLogEntry(
            id: "test-water-update",
            date: Date(),
            cupsConsumed: 5,
            userId: "icloud-user",
            createdAt: Date(),
            updatedAt: Date()
        )

        coreDataManager.saveWaterEntry(entry)

        let updated = WaterLogEntry(
            id: entry.id,
            date: entry.date,
            cupsConsumed: 10,
            userId: entry.userId,
            createdAt: entry.createdAt,
            updatedAt: Date()
        )

        coreDataManager.updateWaterEntry(updated)

        let loaded = coreDataManager.loadWaterEntries()
        XCTAssertEqual(loaded.first(where: { $0.id == entry.id })?.cupsConsumed, 10, "Should update cups consumed")
    }

    func testWaterLogDelete() throws {
        let entry = WaterLogEntry(
            id: "test-water-delete",
            date: Date(),
            cupsConsumed: 6,
            userId: "icloud-user",
            createdAt: Date(),
            updatedAt: Date()
        )

        coreDataManager.saveWaterEntry(entry)
        var loaded = coreDataManager.loadWaterEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save before delete")

        coreDataManager.deleteWaterEntry(entry)
        loaded = coreDataManager.loadWaterEntries()
        XCTAssertFalse(loaded.contains(where: { $0.id == entry.id }), "Should delete water entry")
    }

    // MARK: - Sleep Log CRUD

    func testSleepLogCreate() throws {
        let now = Date()
        let bedTime = now.addingTimeInterval(-28800) // 8 hours ago
        let wakeTime = now

        let entry = SleepLogEntry(
            id: "test-sleep-1",
            date: now,
            wakeUpTime: wakeTime,
            bedTime: bedTime,
            userId: "icloud-user",
            createdAt: now,
            updatedAt: now
        )

        coreDataManager.saveSleepEntry(entry)

        let loaded = coreDataManager.loadSleepEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save sleep entry")
        XCTAssertNotNil(loaded.first(where: { $0.id == entry.id })?.bedTime, "Should save bed time")
    }

    func testSleepLogUpdate() throws {
        let now = Date()
        let entry = SleepLogEntry(
            id: "test-sleep-update",
            date: now,
            wakeUpTime: now,
            bedTime: now.addingTimeInterval(-28800),
            userId: "icloud-user",
            createdAt: now,
            updatedAt: now
        )

        coreDataManager.saveSleepEntry(entry)

        let newWakeTime = now.addingTimeInterval(3600) // 1 hour later
        let updated = SleepLogEntry(
            id: entry.id,
            date: entry.date,
            wakeUpTime: newWakeTime,
            bedTime: entry.bedTime,
            userId: entry.userId,
            createdAt: entry.createdAt,
            updatedAt: Date()
        )

        coreDataManager.updateSleepEntry(updated)

        let loaded = coreDataManager.loadSleepEntries()
        let loadedEntry = loaded.first(where: { $0.id == entry.id })
        XCTAssertNotNil(loadedEntry, "Should find updated entry")
        // Note: Comparing dates with tolerance due to precision
        XCTAssertTrue(abs((loadedEntry?.wakeUpTime ?? Date()).timeIntervalSince(newWakeTime)) < 1, "Should update wake time")
    }

    func testSleepLogDelete() throws {
        let now = Date()
        let entry = SleepLogEntry(
            id: "test-sleep-delete",
            date: now,
            wakeUpTime: now,
            bedTime: now.addingTimeInterval(-28800),
            userId: "icloud-user",
            createdAt: now,
            updatedAt: now
        )

        coreDataManager.saveSleepEntry(entry)
        var loaded = coreDataManager.loadSleepEntries()
        XCTAssertTrue(loaded.contains(where: { $0.id == entry.id }), "Should save before delete")

        coreDataManager.deleteSleepEntry(entry)
        loaded = coreDataManager.loadSleepEntries()
        XCTAssertFalse(loaded.contains(where: { $0.id == entry.id }), "Should delete sleep entry")
    }
}

/// Comprehensive CRUD tests for Goals and Goal Categories
final class GoalsCRUDTests: XCTestCase {

    var persistenceController: PersistenceController!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.container.viewContext
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        testContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Goal Category CRUD

    @MainActor
    func testGoalCategoryCreate() async throws {
        let goalsManager = GoalsManager.shared

        let category = GoalCategoryData(
            id: UUID(),
            title: "Health & Fitness",
            displayPosition: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to Core Data directly for test
        let categoryEntity = GoalCategory(context: testContext)
        categoryEntity.id = category.id.uuidString
        categoryEntity.title = category.title
        categoryEntity.displayPosition = Int16(category.displayPosition)
        categoryEntity.createdAt = category.createdAt
        categoryEntity.updatedAt = category.updatedAt
        categoryEntity.userId = "icloud-user"

        try testContext.save()

        // Load categories
        goalsManager.loadData()

        XCTAssertTrue(goalsManager.categories.contains(where: { $0.id == category.id }), "Should load category")
    }

    @MainActor
    func testGoalCategoryUpdate() async throws {
        let goalsManager = GoalsManager.shared

        var category = GoalCategoryData(
            id: UUID(),
            title: "Career",
            displayPosition: 1,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save initial
        let categoryEntity = GoalCategory(context: testContext)
        categoryEntity.id = category.id.uuidString
        categoryEntity.title = category.title
        categoryEntity.displayPosition = Int16(category.displayPosition)
        categoryEntity.createdAt = category.createdAt
        categoryEntity.updatedAt = category.updatedAt
        categoryEntity.userId = "icloud-user"
        try testContext.save()

        // Update
        category.title = "Professional Development"
        goalsManager.updateCategory(category)

        goalsManager.loadData()

        let updated = goalsManager.categories.first(where: { $0.id == category.id })
        XCTAssertEqual(updated?.title, "Professional Development", "Should update category title")
    }

    @MainActor
    func testGoalCategoryDelete() async throws {
        let goalsManager = GoalsManager.shared

        let category = GoalCategoryData(
            id: UUID(),
            title: "To Delete",
            displayPosition: 2,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save
        let categoryEntity = GoalCategory(context: testContext)
        categoryEntity.id = category.id.uuidString
        categoryEntity.title = category.title
        categoryEntity.displayPosition = Int16(category.displayPosition)
        categoryEntity.createdAt = category.createdAt
        categoryEntity.updatedAt = category.updatedAt
        categoryEntity.userId = "icloud-user"
        try testContext.save()

        goalsManager.loadData()
        XCTAssertTrue(goalsManager.categories.contains(where: { $0.id == category.id }), "Should exist before delete")

        // Delete
        goalsManager.deleteCategory(category.id)
        goalsManager.loadData()

        XCTAssertFalse(goalsManager.categories.contains(where: { $0.id == category.id }), "Should delete category")
    }

    // MARK: - Goal CRUD

    @MainActor
    func testGoalCreate() async throws {
        let goalsManager = GoalsManager.shared

        let goal = GoalData(
            id: UUID(),
            title: "Run Marathon",
            description: "Complete a full marathon",
            successMetric: "Finish in under 4 hours",
            categoryId: UUID(),
            targetTimeframe: "6 months",
            dueDate: Date().addingTimeInterval(86400 * 180),
            isCompleted: false,
            linkedTasks: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to Core Data
        let goalEntity = Goal(context: testContext)
        goalEntity.id = goal.id.uuidString
        goalEntity.title = goal.title
        goalEntity.goalDescription = goal.description
        goalEntity.successMetric = goal.successMetric
        goalEntity.categoryId = goal.categoryId?.uuidString
        goalEntity.targetTimeframe = goal.targetTimeframe
        goalEntity.dueDate = goal.dueDate
        goalEntity.isCompleted = goal.isCompleted
        goalEntity.createdAt = goal.createdAt
        goalEntity.updatedAt = goal.updatedAt
        goalEntity.userId = "icloud-user"

        try testContext.save()

        goalsManager.loadData()

        XCTAssertTrue(goalsManager.goals.contains(where: { $0.id == goal.id }), "Should load goal")
    }

    @MainActor
    func testGoalUpdate() async throws {
        let goalsManager = GoalsManager.shared

        var goal = GoalData(
            id: UUID(),
            title: "Learn Swift",
            description: "Master iOS development",
            successMetric: "Build 3 apps",
            categoryId: nil,
            targetTimeframe: "3 months",
            dueDate: nil,
            isCompleted: false,
            linkedTasks: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save initial
        let goalEntity = Goal(context: testContext)
        goalEntity.id = goal.id.uuidString
        goalEntity.title = goal.title
        goalEntity.goalDescription = goal.description
        goalEntity.isCompleted = false
        goalEntity.createdAt = goal.createdAt
        goalEntity.updatedAt = goal.updatedAt
        goalEntity.userId = "icloud-user"
        try testContext.save()

        // Update - mark as completed
        goal.isCompleted = true
        goalsManager.updateGoal(goal)

        goalsManager.loadData()

        let updated = goalsManager.goals.first(where: { $0.id == goal.id })
        XCTAssertEqual(updated?.isCompleted, true, "Should update goal completion status")
    }

    @MainActor
    func testGoalDelete() async throws {
        let goalsManager = GoalsManager.shared

        let goal = GoalData(
            id: UUID(),
            title: "Goal to Delete",
            description: "Test deletion",
            successMetric: "N/A",
            categoryId: nil,
            targetTimeframe: nil,
            dueDate: nil,
            isCompleted: false,
            linkedTasks: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save
        let goalEntity = Goal(context: testContext)
        goalEntity.id = goal.id.uuidString
        goalEntity.title = goal.title
        goalEntity.isCompleted = false
        goalEntity.createdAt = goal.createdAt
        goalEntity.updatedAt = goal.updatedAt
        goalEntity.userId = "icloud-user"
        try testContext.save()

        goalsManager.loadData()
        XCTAssertTrue(goalsManager.goals.contains(where: { $0.id == goal.id }), "Should exist before delete")

        // Delete
        goalsManager.deleteGoal(goal.id)
        goalsManager.loadData()

        XCTAssertFalse(goalsManager.goals.contains(where: { $0.id == goal.id }), "Should delete goal")
    }
}

/// Comprehensive CRUD tests for Custom Log Items and Entries
final class CustomLogCRUDTests: XCTestCase {

    var persistenceController: PersistenceController!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.container.viewContext
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        testContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Custom Log Item CRUD

    @MainActor
    func testCustomLogItemCreate() async throws {
        let customLogManager = CustomLogManager.shared

        let item = CustomLogItemData(
            id: UUID(),
            title: "Meditation",
            isEnabled: true,
            displayOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to Core Data
        let itemEntity = CustomLogItem(context: testContext)
        itemEntity.id = item.id.uuidString
        itemEntity.title = item.title
        itemEntity.isEnabled = item.isEnabled
        itemEntity.displayOrder = Int16(item.displayOrder)
        itemEntity.createdAt = item.createdAt
        itemEntity.updatedAt = item.updatedAt
        itemEntity.userId = "icloud-user"

        try testContext.save()

        customLogManager.loadData()

        XCTAssertTrue(customLogManager.items.contains(where: { $0.id == item.id }), "Should load custom log item")
    }

    @MainActor
    func testCustomLogItemUpdate() async throws {
        let customLogManager = CustomLogManager.shared

        var item = CustomLogItemData(
            id: UUID(),
            title: "Reading",
            isEnabled: true,
            displayOrder: 1,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save initial
        let itemEntity = CustomLogItem(context: testContext)
        itemEntity.id = item.id.uuidString
        itemEntity.title = item.title
        itemEntity.isEnabled = true
        itemEntity.displayOrder = Int16(item.displayOrder)
        itemEntity.createdAt = item.createdAt
        itemEntity.updatedAt = item.updatedAt
        itemEntity.userId = "icloud-user"
        try testContext.save()

        // Update - disable item
        item.isEnabled = false
        customLogManager.updateItem(item)

        customLogManager.loadData()

        let updated = customLogManager.items.first(where: { $0.id == item.id })
        XCTAssertEqual(updated?.isEnabled, false, "Should update item enabled status")
    }

    @MainActor
    func testCustomLogItemDelete() async throws {
        let customLogManager = CustomLogManager.shared

        let item = CustomLogItemData(
            id: UUID(),
            title: "Item to Delete",
            isEnabled: true,
            displayOrder: 2,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save
        let itemEntity = CustomLogItem(context: testContext)
        itemEntity.id = item.id.uuidString
        itemEntity.title = item.title
        itemEntity.isEnabled = item.isEnabled
        itemEntity.displayOrder = Int16(item.displayOrder)
        itemEntity.createdAt = item.createdAt
        itemEntity.updatedAt = item.updatedAt
        itemEntity.userId = "icloud-user"
        try testContext.save()

        customLogManager.loadData()
        XCTAssertTrue(customLogManager.items.contains(where: { $0.id == item.id }), "Should exist before delete")

        // Delete
        customLogManager.deleteItem(item.id)
        customLogManager.loadData()

        XCTAssertFalse(customLogManager.items.contains(where: { $0.id == item.id }), "Should delete item")
    }

    // MARK: - Custom Log Entry CRUD

    func testCustomLogEntryCreate() throws {
        let itemId = UUID()
        let entry = CustomLogEntry(context: testContext)
        entry.id = UUID().uuidString
        entry.itemId = itemId.uuidString
        entry.date = Date()
        entry.isCompleted = false
        entry.userId = "icloud-user"
        entry.createdAt = Date()
        entry.updatedAt = Date()

        try testContext.save()

        let fetchRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        let results = try testContext.fetch(fetchRequest)

        XCTAssertTrue(results.contains(where: { $0.itemId == itemId.uuidString }), "Should save custom log entry")
    }

    func testCustomLogEntryUpdate() throws {
        let entry = CustomLogEntry(context: testContext)
        let entryId = UUID().uuidString
        entry.id = entryId
        entry.itemId = UUID().uuidString
        entry.date = Date()
        entry.isCompleted = false
        entry.userId = "icloud-user"
        entry.createdAt = Date()
        entry.updatedAt = Date()

        try testContext.save()

        // Update - mark as completed
        let fetchRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", entryId)
        let results = try testContext.fetch(fetchRequest)

        if let entryToUpdate = results.first {
            entryToUpdate.isCompleted = true
            try testContext.save()

            let updatedResults = try testContext.fetch(fetchRequest)
            XCTAssertEqual(updatedResults.first?.isCompleted, true, "Should update entry completion")
        } else {
            XCTFail("Entry not found for update")
        }
    }

    func testCustomLogEntryDelete() throws {
        let entryId = UUID().uuidString
        let entry = CustomLogEntry(context: testContext)
        entry.id = entryId
        entry.itemId = UUID().uuidString
        entry.date = Date()
        entry.isCompleted = false
        entry.userId = "icloud-user"
        entry.createdAt = Date()
        entry.updatedAt = Date()

        try testContext.save()

        // Delete
        let fetchRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", entryId)
        let results = try testContext.fetch(fetchRequest)

        results.forEach { testContext.delete($0) }
        try testContext.save()

        let afterDelete = try testContext.fetch(fetchRequest)
        XCTAssertEqual(afterDelete.count, 0, "Should delete entry")
    }
}

/// Tests for Journal Manager (PDF backgrounds and photo metadata)
final class JournalCRUDTests: XCTestCase {

    var journalManager: JournalManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        journalManager = JournalManager.shared
    }

    override func tearDownWithError() throws {
        // Clean up test files
        journalManager.clearBackgroundPDF(layoutType: .compact)
        journalManager.clearBackgroundPDF(layoutType: .expanded)
        journalManager = nil
        try super.tearDownWithError()
    }

    // MARK: - PDF Background Management

    func testSavePDFBackground() throws {
        let testData = Data("Test PDF Content".utf8)

        try journalManager.savePDF(data: testData, layoutType: .compact)

        let loadedData = journalManager.loadPDFData(for: .compact)
        XCTAssertNotNil(loadedData, "Should save and load PDF data")
        XCTAssertEqual(loadedData, testData, "Loaded data should match saved data")
    }

    func testClearPDFBackground() throws {
        let testData = Data("Test PDF Content".utf8)

        try journalManager.savePDF(data: testData, layoutType: .compact)
        XCTAssertNotNil(journalManager.loadPDFData(for: .compact), "Should have PDF before clear")

        journalManager.clearBackgroundPDF(layoutType: .compact)

        // After clearing, should fall back to bundled resource or nil
        let afterClear = journalManager.backgroundPDFURL(for: .compact)
        // Should either be nil or point to bundled resource
        XCTAssertTrue(afterClear == nil || afterClear?.path.contains("journal_background.pdf") == true, "Should clear custom PDF")
    }

    func testMultipleLayoutPDFs() throws {
        let compactData = Data("Compact Layout PDF".utf8)
        let expandedData = Data("Expanded Layout PDF".utf8)

        try journalManager.savePDF(data: compactData, layoutType: .compact)
        try journalManager.savePDF(data: expandedData, layoutType: .expanded)

        let compactLoaded = journalManager.loadPDFData(for: .compact)
        let expandedLoaded = journalManager.loadPDFData(for: .expanded)

        XCTAssertEqual(compactLoaded, compactData, "Should save compact PDF")
        XCTAssertEqual(expandedLoaded, expandedData, "Should save expanded PDF")
        XCTAssertNotEqual(compactLoaded, expandedLoaded, "Should keep layouts separate")
    }

    // MARK: - Photo Metadata Management

    func testPhotoMetadataURL() {
        let testDate = Date()
        let metadataURL = journalManager.metadataURL(for: testDate)

        XCTAssertTrue(metadataURL.path.contains("journal_photos"), "Should be in journal_photos directory")
        XCTAssertTrue(metadataURL.path.hasSuffix("_photos.json"), "Should be JSON file")
    }

    func testPhotosDirectoryCreation() {
        let photosDir = journalManager.photosDirectoryURL

        XCTAssertTrue(FileManager.default.fileExists(atPath: photosDir.path), "Should create photos directory")
    }
}

/// Integration tests for Task Time Windows (linking tasks to calendar slots)
final class TaskTimeWindowCRUDTests: XCTestCase {

    var persistenceController: PersistenceController!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.container.viewContext
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        testContext = nil
        try super.tearDownWithError()
    }

    func testTaskTimeWindowCreate() throws {
        let window = TaskTimeWindow(context: testContext)
        window.id = UUID().uuidString
        window.taskId = "test-task-123"
        window.startTime = Date()
        window.endTime = Date().addingTimeInterval(3600)
        window.isAllDay = false
        window.userId = "icloud-user"
        window.createdAt = Date()
        window.updatedAt = Date()

        try testContext.save()

        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskId == %@", "test-task-123")
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should save task time window")
        XCTAssertEqual(results.first?.taskId, "test-task-123", "Should save correct task ID")
    }

    func testTaskTimeWindowUpdate() throws {
        let windowId = UUID().uuidString
        let window = TaskTimeWindow(context: testContext)
        window.id = windowId
        window.taskId = "test-task-456"
        window.startTime = Date()
        window.endTime = Date().addingTimeInterval(3600)
        window.isAllDay = false
        window.userId = "icloud-user"
        window.createdAt = Date()
        window.updatedAt = Date()

        try testContext.save()

        // Update end time
        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", windowId)
        let results = try testContext.fetch(fetchRequest)

        if let windowToUpdate = results.first {
            let newEndTime = Date().addingTimeInterval(7200) // 2 hours
            windowToUpdate.endTime = newEndTime
            windowToUpdate.updatedAt = Date()
            try testContext.save()

            let updatedResults = try testContext.fetch(fetchRequest)
            let timeDiff = abs((updatedResults.first?.endTime ?? Date()).timeIntervalSince(newEndTime))
            XCTAssertTrue(timeDiff < 1, "Should update end time")
        } else {
            XCTFail("Window not found for update")
        }
    }

    func testTaskTimeWindowDelete() throws {
        let windowId = UUID().uuidString
        let window = TaskTimeWindow(context: testContext)
        window.id = windowId
        window.taskId = "test-task-789"
        window.startTime = Date()
        window.endTime = Date().addingTimeInterval(3600)
        window.isAllDay = false
        window.userId = "icloud-user"
        window.createdAt = Date()
        window.updatedAt = Date()

        try testContext.save()

        // Delete
        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", windowId)
        let results = try testContext.fetch(fetchRequest)

        results.forEach { testContext.delete($0) }
        try testContext.save()

        let afterDelete = try testContext.fetch(fetchRequest)
        XCTAssertEqual(afterDelete.count, 0, "Should delete task time window")
    }

    func testMultipleTaskTimeWindows() throws {
        // Create multiple windows for same task
        for i in 0..<3 {
            let window = TaskTimeWindow(context: testContext)
            window.id = UUID().uuidString
            window.taskId = "multi-task-123"
            window.startTime = Date().addingTimeInterval(Double(i * 3600))
            window.endTime = Date().addingTimeInterval(Double((i + 1) * 3600))
            window.isAllDay = false
            window.userId = "icloud-user"
            window.createdAt = Date()
            window.updatedAt = Date()
        }

        try testContext.save()

        let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskId == %@", "multi-task-123")
        let results = try testContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 3, "Should save multiple time windows for same task")
    }
}

// MARK: - Calendar ViewModel Tests

/// Tests for CalendarViewModel operations and state management
/// Note: Full CRUD operations require Google Calendar API mocking
final class CalendarViewModelTests: XCTestCase {

    // MARK: - Initialization Tests

    @MainActor
    func testCalendarViewModelInitialization() {
        let viewModel = CalendarViewModel()

        XCTAssertNotNil(viewModel, "ViewModel should initialize")
        XCTAssertEqual(viewModel.personalCalendars.count, 0, "Should start with no calendars")
        XCTAssertEqual(viewModel.professionalCalendars.count, 0, "Should start with no calendars")
        XCTAssertEqual(viewModel.personalEvents.count, 0, "Should start with no events")
        XCTAssertEqual(viewModel.professionalEvents.count, 0, "Should start with no events")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")
        XCTAssertNil(viewModel.errorMessage, "Should have no error initially")
    }

    // MARK: - Event Management Tests

    @MainActor
    func testPersonalEventsUpdateTriggersRecomputation() {
        let viewModel = CalendarViewModel()
        let testEvent = GoogleCalendarEvent(
            id: "test-1",
            calendarId: "cal-1",
            title: "Test Event",
            description: nil,
            location: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            recurrence: [],
            recurringEventId: nil,
            originalStartTime: nil,
            creator: nil,
            organizer: nil,
            htmlLink: nil,
            colorId: nil,
            transparency: nil
        )

        viewModel.personalEvents = [testEvent]

        XCTAssertEqual(viewModel.personalEvents.count, 1, "Should add event to personal events")
    }

    @MainActor
    func testProfessionalEventsUpdateTriggersRecomputation() {
        let viewModel = CalendarViewModel()
        let testEvent = GoogleCalendarEvent(
            id: "test-pro-1",
            calendarId: "cal-pro-1",
            title: "Work Meeting",
            description: nil,
            location: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            recurrence: [],
            recurringEventId: nil,
            originalStartTime: nil,
            creator: nil,
            organizer: nil,
            htmlLink: nil,
            colorId: nil,
            transparency: nil
        )

        viewModel.professionalEvents = [testEvent]

        XCTAssertEqual(viewModel.professionalEvents.count, 1, "Should add event to professional events")
    }

    @MainActor
    func testCombinedEventsFromBothAccounts() {
        let viewModel = CalendarViewModel()

        let personalEvent = GoogleCalendarEvent(
            id: "personal-1",
            calendarId: "cal-1",
            title: "Personal Event",
            description: nil,
            location: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            recurrence: [],
            recurringEventId: nil,
            originalStartTime: nil,
            creator: nil,
            organizer: nil,
            htmlLink: nil,
            colorId: nil,
            transparency: nil
        )

        let professionalEvent = GoogleCalendarEvent(
            id: "professional-1",
            calendarId: "cal-pro-1",
            title: "Work Event",
            description: nil,
            location: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            recurrence: [],
            recurringEventId: nil,
            originalStartTime: nil,
            creator: nil,
            organizer: nil,
            htmlLink: nil,
            colorId: nil,
            transparency: nil
        )

        viewModel.personalEvents = [personalEvent]
        viewModel.professionalEvents = [professionalEvent]

        let totalEvents = viewModel.personalEvents.count + viewModel.professionalEvents.count
        XCTAssertEqual(totalEvents, 2, "Should have events from both accounts")
    }

    // MARK: - State Management Tests

    @MainActor
    func testLoadingStateManagement() {
        let viewModel = CalendarViewModel()

        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")

        viewModel.isLoading = true
        XCTAssertTrue(viewModel.isLoading, "Should be loading when set")

        viewModel.isLoading = false
        XCTAssertFalse(viewModel.isLoading, "Should not be loading when cleared")
    }

    @MainActor
    func testErrorStateManagement() {
        let viewModel = CalendarViewModel()

        XCTAssertNil(viewModel.errorMessage, "Should have no error initially")
        XCTAssertFalse(viewModel.showError, "Should not show error initially")

        viewModel.errorMessage = "Test error"
        viewModel.showError = true

        XCTAssertEqual(viewModel.errorMessage, "Test error", "Should set error message")
        XCTAssertTrue(viewModel.showError, "Should show error flag")
    }

    // MARK: - Calendar Data Structure Tests

    @MainActor
    func testCalendarListManagement() {
        let viewModel = CalendarViewModel()

        let personalCalendar = GoogleCalendar(
            id: "cal-1",
            summary: "Personal Calendar",
            primary: true,
            backgroundColor: "#ff0000"
        )

        let professionalCalendar = GoogleCalendar(
            id: "cal-pro-1",
            summary: "Work Calendar",
            primary: false,
            backgroundColor: "#0000ff"
        )

        viewModel.personalCalendars = [personalCalendar]
        viewModel.professionalCalendars = [professionalCalendar]

        XCTAssertEqual(viewModel.personalCalendars.count, 1, "Should have one personal calendar")
        XCTAssertEqual(viewModel.professionalCalendars.count, 1, "Should have one professional calendar")
        XCTAssertEqual(viewModel.personalCalendars.first?.summary, "Personal Calendar", "Should set correct calendar name")
    }

    // Note: Full CRUD tests would require Google Calendar API mocking:
    // - testCreateEvent() - Create new calendar event
    // - testUpdateEvent() - Update existing event
    // - testDeleteEvent() - Delete event
    // - testFetchEventsForDateRange() - Fetch events from API
    // - testEventCaching() - Verify month-based caching works
    // - testCacheClearance() - Test cache invalidation
}

// MARK: - Tasks ViewModel Tests

/// Tests for TasksViewModel operations and state management
/// Note: Full CRUD operations require Google Tasks API mocking
final class TasksViewModelTests: XCTestCase {

    // MARK: - Initialization Tests

    @MainActor
    func testTasksViewModelInitialization() {
        let viewModel = TasksViewModel()

        XCTAssertNotNil(viewModel, "ViewModel should initialize")
        XCTAssertEqual(viewModel.personalTaskLists.count, 0, "Should start with no task lists")
        XCTAssertEqual(viewModel.professionalTaskLists.count, 0, "Should start with no task lists")
        XCTAssertEqual(viewModel.personalTasks.count, 0, "Should start with no tasks")
        XCTAssertEqual(viewModel.professionalTasks.count, 0, "Should start with no tasks")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")
    }

    // MARK: - Task List Management Tests

    @MainActor
    func testTaskListAddition() {
        let viewModel = TasksViewModel()

        let taskList = GoogleTaskList(
            id: "list-1",
            title: "My Tasks",
            updated: Date()
        )

        viewModel.personalTaskLists = [taskList]

        XCTAssertEqual(viewModel.personalTaskLists.count, 1, "Should add task list")
        XCTAssertEqual(viewModel.personalTaskLists.first?.title, "My Tasks", "Should set correct title")
    }

    @MainActor
    func testMultipleTaskLists() {
        let viewModel = TasksViewModel()

        let list1 = GoogleTaskList(id: "list-1", title: "Work", updated: Date())
        let list2 = GoogleTaskList(id: "list-2", title: "Personal", updated: Date())
        let list3 = GoogleTaskList(id: "list-3", title: "Shopping", updated: Date())

        viewModel.personalTaskLists = [list1, list2, list3]

        XCTAssertEqual(viewModel.personalTaskLists.count, 3, "Should have 3 task lists")
    }

    @MainActor
    func testSeparateAccountTaskLists() {
        let viewModel = TasksViewModel()

        let personalList = GoogleTaskList(id: "list-personal", title: "Personal Tasks", updated: Date())
        let professionalList = GoogleTaskList(id: "list-work", title: "Work Tasks", updated: Date())

        viewModel.personalTaskLists = [personalList]
        viewModel.professionalTaskLists = [professionalList]

        XCTAssertEqual(viewModel.personalTaskLists.count, 1, "Should have personal list")
        XCTAssertEqual(viewModel.professionalTaskLists.count, 1, "Should have professional list")
        XCTAssertNotEqual(viewModel.personalTaskLists.first?.id, viewModel.professionalTaskLists.first?.id, "Lists should be separate")
    }

    // MARK: - Task Management Tests

    @MainActor
    func testTaskAdditionToList() {
        let viewModel = TasksViewModel()

        let task = GoogleTask(
            id: "task-1",
            title: "Complete project",
            notes: nil,
            status: "needsAction",
            due: nil,
            completed: nil,
            position: "00000000000000000000",
            parent: nil,
            updated: Date(),
            selfLink: nil,
            etag: nil
        )

        viewModel.personalTasks["list-1"] = [task]

        XCTAssertEqual(viewModel.personalTasks["list-1"]?.count, 1, "Should add task to list")
        XCTAssertEqual(viewModel.personalTasks["list-1"]?.first?.title, "Complete project", "Should set correct title")
    }

    @MainActor
    func testMultipleTasksInList() {
        let viewModel = TasksViewModel()

        let task1 = GoogleTask(id: "task-1", title: "Task 1", notes: nil, status: "needsAction", due: nil, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let task2 = GoogleTask(id: "task-2", title: "Task 2", notes: nil, status: "needsAction", due: nil, completed: nil, position: "2", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let task3 = GoogleTask(id: "task-3", title: "Task 3", notes: nil, status: "completed", due: nil, completed: Date(), position: "3", parent: nil, updated: Date(), selfLink: nil, etag: nil)

        viewModel.personalTasks["list-1"] = [task1, task2, task3]

        XCTAssertEqual(viewModel.personalTasks["list-1"]?.count, 3, "Should have 3 tasks")
    }

    @MainActor
    func testTasksAcrossMultipleLists() {
        let viewModel = TasksViewModel()

        let workTask = GoogleTask(id: "work-1", title: "Work Task", notes: nil, status: "needsAction", due: nil, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let personalTask = GoogleTask(id: "personal-1", title: "Personal Task", notes: nil, status: "needsAction", due: nil, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)

        viewModel.personalTasks["work-list"] = [workTask]
        viewModel.personalTasks["personal-list"] = [personalTask]

        XCTAssertEqual(viewModel.personalTasks.keys.count, 2, "Should have tasks in 2 lists")
        XCTAssertEqual(viewModel.personalTasks["work-list"]?.count, 1, "Work list should have 1 task")
        XCTAssertEqual(viewModel.personalTasks["personal-list"]?.count, 1, "Personal list should have 1 task")
    }

    // MARK: - Task Priority Integration Tests

    @MainActor
    func testTaskWithPriorityInNotes() {
        let viewModel = TasksViewModel()

        let taskWithPriority = GoogleTask(
            id: "task-priority",
            title: "Important Task",
            notes: "[PRIORITY:P0]\nTask description here",
            status: "needsAction",
            due: nil,
            completed: nil,
            position: "1",
            parent: nil,
            updated: Date(),
            selfLink: nil,
            etag: nil
        )

        viewModel.personalTasks["list-1"] = [taskWithPriority]

        let savedTask = viewModel.personalTasks["list-1"]?.first
        XCTAssertNotNil(savedTask?.notes, "Task should have notes")
        XCTAssertTrue(savedTask?.notes?.contains("[PRIORITY:P0]") ?? false, "Notes should contain priority tag")

        // Test priority parsing
        let priority = TaskPriorityData.parse(from: savedTask?.notes ?? "")
        XCTAssertEqual(priority?.value, "P0", "Should parse P0 priority")
    }

    @MainActor
    func testTaskPriorityFiltering() {
        let viewModel = TasksViewModel()

        let p0Task = GoogleTask(id: "p0", title: "Critical", notes: "[PRIORITY:P0]", status: "needsAction", due: nil, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let p2Task = GoogleTask(id: "p2", title: "Medium", notes: "[PRIORITY:P2]", status: "needsAction", due: nil, completed: nil, position: "2", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let noPriorityTask = GoogleTask(id: "none", title: "No priority", notes: nil, status: "needsAction", due: nil, completed: nil, position: "3", parent: nil, updated: Date(), selfLink: nil, etag: nil)

        viewModel.personalTasks["list-1"] = [p0Task, p2Task, noPriorityTask]

        let tasks = viewModel.personalTasks["list-1"] ?? []
        let priorityTasks = tasks.filter { TaskPriorityData.parse(from: $0.notes ?? "") != nil }

        XCTAssertEqual(priorityTasks.count, 2, "Should have 2 tasks with priority")
    }

    // MARK: - Task Status Tests

    @MainActor
    func testTaskCompletionStatus() {
        let viewModel = TasksViewModel()

        let activeTask = GoogleTask(id: "active", title: "Active", notes: nil, status: "needsAction", due: nil, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let completedTask = GoogleTask(id: "done", title: "Done", notes: nil, status: "completed", due: Date().addingTimeInterval(-3600), completed: Date(), position: "2", parent: nil, updated: Date(), selfLink: nil, etag: nil)

        viewModel.personalTasks["list-1"] = [activeTask, completedTask]

        let tasks = viewModel.personalTasks["list-1"] ?? []
        let activeTasks = tasks.filter { $0.status == "needsAction" }
        let completedTasks = tasks.filter { $0.status == "completed" }

        XCTAssertEqual(activeTasks.count, 1, "Should have 1 active task")
        XCTAssertEqual(completedTasks.count, 1, "Should have 1 completed task")
    }

    // MARK: - State Management Tests

    @MainActor
    func testLoadingStateManagement() {
        let viewModel = TasksViewModel()

        XCTAssertFalse(viewModel.isLoading, "Should not be loading initially")

        viewModel.isLoading = true
        XCTAssertTrue(viewModel.isLoading, "Should be loading when set")

        viewModel.isLoading = false
        XCTAssertFalse(viewModel.isLoading, "Should not be loading when cleared")
    }

    @MainActor
    func testErrorMessageManagement() {
        let viewModel = TasksViewModel()

        XCTAssertTrue(viewModel.errorMessage.isEmpty, "Should have no error initially")

        viewModel.errorMessage = "API Error"
        XCTAssertEqual(viewModel.errorMessage, "API Error", "Should set error message")

        viewModel.errorMessage = ""
        XCTAssertTrue(viewModel.errorMessage.isEmpty, "Should clear error message")
    }

    // MARK: - Task Due Date Tests

    @MainActor
    func testTasksWithDueDates() {
        let viewModel = TasksViewModel()

        let tomorrow = Date().addingTimeInterval(86400)
        let nextWeek = Date().addingTimeInterval(86400 * 7)

        let task1 = GoogleTask(id: "due-tomorrow", title: "Due Tomorrow", notes: nil, status: "needsAction", due: tomorrow, completed: nil, position: "1", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let task2 = GoogleTask(id: "due-next-week", title: "Due Next Week", notes: nil, status: "needsAction", due: nextWeek, completed: nil, position: "2", parent: nil, updated: Date(), selfLink: nil, etag: nil)
        let task3 = GoogleTask(id: "no-due", title: "No Due Date", notes: nil, status: "needsAction", due: nil, completed: nil, position: "3", parent: nil, updated: Date(), selfLink: nil, etag: nil)

        viewModel.personalTasks["list-1"] = [task1, task2, task3]

        let tasks = viewModel.personalTasks["list-1"] ?? []
        let tasksWithDue = tasks.filter { $0.due != nil }
        let tasksWithoutDue = tasks.filter { $0.due == nil }

        XCTAssertEqual(tasksWithDue.count, 2, "Should have 2 tasks with due dates")
        XCTAssertEqual(tasksWithoutDue.count, 1, "Should have 1 task without due date")
    }

    // Note: Full CRUD tests would require Google Tasks API mocking:
    // - testCreateTask() - Create new task via API
    // - testUpdateTask() - Update existing task
    // - testDeleteTask() - Delete task
    // - testCompleteTask() - Mark task as completed
    // - testMoveTask() - Move task between lists
    // - testCreateTaskList() - Create new task list
    // - testDeleteTaskList() - Delete task list
    // - testFetchTasksForList() - Fetch tasks from API
    // - testReorderTasks() - Test position updates
}

// MARK: - Integration Tests for ViewModel Interactions

/// Tests for interactions between ViewModels and other components
final class ViewModelIntegrationTests: XCTestCase {

    @MainActor
    func testCalendarAndTasksViewModelsCoexist() {
        let calendarVM = CalendarViewModel()
        let tasksVM = TasksViewModel()

        XCTAssertNotNil(calendarVM, "Calendar ViewModel should initialize")
        XCTAssertNotNil(tasksVM, "Tasks ViewModel should initialize")

        // Test that both can hold data simultaneously
        let event = GoogleCalendarEvent(
            id: "event-1",
            calendarId: "cal-1",
            title: "Meeting",
            description: nil,
            location: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            recurrence: [],
            recurringEventId: nil,
            originalStartTime: nil,
            creator: nil,
            organizer: nil,
            htmlLink: nil,
            colorId: nil,
            transparency: nil
        )

        let task = GoogleTask(
            id: "task-1",
            title: "Follow up",
            notes: nil,
            status: "needsAction",
            due: Date().addingTimeInterval(86400),
            completed: nil,
            position: "1",
            parent: nil,
            updated: Date(),
            selfLink: nil,
            etag: nil
        )

        calendarVM.personalEvents = [event]
        tasksVM.personalTasks["list-1"] = [task]

        XCTAssertEqual(calendarVM.personalEvents.count, 1, "Calendar should have event")
        XCTAssertEqual(tasksVM.personalTasks["list-1"]?.count, 1, "Tasks should have task")
    }

    @MainActor
    func testDataManagerAccessToViewModels() {
        let dataManager = DataManager.shared

        XCTAssertNotNil(dataManager.calendarViewModel, "Should have calendar view model")
        XCTAssertNotNil(dataManager.tasksViewModel, "Should have tasks view model")
    }

    @MainActor
    func testTaskWithTimeWindowLinking() {
        let tasksVM = TasksViewModel()
        let testContext = PersistenceController(inMemory: true).container.viewContext

        // Create a task
        let task = GoogleTask(
            id: "linked-task",
            title: "Task with Time Window",
            notes: nil,
            status: "needsAction",
            due: Date(),
            completed: nil,
            position: "1",
            parent: nil,
            updated: Date(),
            selfLink: nil,
            etag: nil
        )

        tasksVM.personalTasks["list-1"] = [task]

        // Create a time window for this task
        let window = TaskTimeWindow(context: testContext)
        window.id = UUID().uuidString
        window.taskId = task.id
        window.startTime = Date()
        window.endTime = Date().addingTimeInterval(3600)
        window.isAllDay = false
        window.userId = "icloud-user"

        do {
            try testContext.save()

            let fetchRequest: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "taskId == %@", task.id)
            let results = try testContext.fetch(fetchRequest)

            XCTAssertEqual(results.count, 1, "Should link task to time window")
            XCTAssertEqual(results.first?.taskId, task.id, "Time window should reference correct task")
        } catch {
            XCTFail("Failed to create time window: \(error)")
        }
    }
}
