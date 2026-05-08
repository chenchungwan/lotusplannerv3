//
//  TaskSchedulerTests.swift
//  LotusPlannerV3Tests
//
//  Pure-logic tests for TaskScheduler. The local-yyyy-MM-dd format
//  caught a previous bug where UTC formatting of `task.due` rolled
//  the date forward by one day in negative-offset timezones — these
//  tests guard the regression at the format-string boundary.
//

import XCTest
@testable import LotusPlannerV3

@MainActor
final class TaskSchedulerTests: XCTestCase {

    // MARK: - formatDueDate

    func testFormatDueDate_ProducesLocalDateString() {
        let comps = DateComponents(year: 2026, month: 5, day: 8, hour: 14, minute: 30)
        let date = Calendar.current.date(from: comps)!
        let formatted = TaskScheduler.formatDueDate(date)
        XCTAssertEqual(formatted, "2026-05-08")
    }

    /// Late-evening edge case in a negative-offset (e.g. PDT/UTC-7)
    /// timezone. With a UTC formatter, 23:30 PDT serializes as the
    /// next calendar day in UTC, which Google Tasks then stores as
    /// "tomorrow." The local formatter must keep the user's date.
    func testFormatDueDate_LateEvening_StaysOnLocalDay() {
        // Build a date at 23:30 in the current timezone, regardless of
        // what timezone the test runs in.
        let comps = DateComponents(year: 2026, month: 5, day: 8, hour: 23, minute: 30)
        let date = Calendar.current.date(from: comps)!

        let formatted = TaskScheduler.formatDueDate(date)

        // Verify the formatted string matches the local-day component
        // of `date`. If TaskScheduler regresses to a UTC formatter and
        // the test runs in a negative-offset timezone, the day will
        // roll forward and this assertion will fail.
        let localDay = Calendar.current.component(.day, from: date)
        let expected = String(format: "2026-05-%02d", localDay)
        XCTAssertEqual(formatted, expected)
    }

    func testFormatDueDate_StableAcrossSecondsAndSubseconds() {
        let comps = DateComponents(year: 2026, month: 1, day: 15, hour: 9, minute: 0, second: 0)
        let baseDate = Calendar.current.date(from: comps)!
        let withSubseconds = baseDate.addingTimeInterval(0.4)

        XCTAssertEqual(TaskScheduler.formatDueDate(baseDate),
                       TaskScheduler.formatDueDate(withSubseconds))
    }

    // MARK: - resolvedDuration(forTaskId:fallback:)

    func testResolvedDuration_NoWindow_ReturnsFallback() {
        let randomId = "task-with-no-window-\(UUID().uuidString)"
        let duration = TaskScheduler.resolvedDuration(forTaskId: randomId, fallback: 1234)
        XCTAssertEqual(duration, 1234)
    }

    func testResolvedDuration_DefaultFallback_Is30Minutes() {
        let randomId = "task-with-no-window-\(UUID().uuidString)"
        let duration = TaskScheduler.resolvedDuration(forTaskId: randomId)
        XCTAssertEqual(duration, 30 * 60)
    }

    /// When a stored window exists and is non-all-day, return its
    /// length. Verifies the lookup goes through TaskTimeWindowManager
    /// and isn't quietly clamped.
    func testResolvedDuration_WithStoredWindow_ReturnsActualDuration() {
        let id = "perf-test-task-\(UUID().uuidString)"
        let start = Date()
        let end = start.addingTimeInterval(45 * 60) // 45 minutes
        TaskTimeWindowManager.shared.saveTimeWindow(
            taskId: id,
            startTime: start,
            endTime: end,
            isAllDay: false
        )
        defer { TaskTimeWindowManager.shared.deleteTimeWindow(for: id) }

        let duration = TaskScheduler.resolvedDuration(forTaskId: id, fallback: 999)
        XCTAssertEqual(duration, 45 * 60)
    }

    func testResolvedDuration_AllDayWindow_FallsBackToDefault() {
        let id = "all-day-test-task-\(UUID().uuidString)"
        let start = Date()
        TaskTimeWindowManager.shared.saveTimeWindow(
            taskId: id,
            startTime: start,
            endTime: start.addingTimeInterval(8 * 3600),
            isAllDay: true
        )
        defer { TaskTimeWindowManager.shared.deleteTimeWindow(for: id) }

        let duration = TaskScheduler.resolvedDuration(forTaskId: id, fallback: 1234)
        XCTAssertEqual(duration, 1234, "An all-day window should not be treated as a duration source")
    }
}
