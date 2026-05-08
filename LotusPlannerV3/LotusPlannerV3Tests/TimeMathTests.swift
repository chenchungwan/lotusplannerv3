//
//  TimeMathTests.swift
//  LotusPlannerV3Tests
//
//  Pure-logic tests for TimeMath. The "next half-hour boundary" rule
//  underlies AddEventView, AddTaskView, and BulkEditComponents — a
//  regression here misroutes new events/tasks across all three.
//

import XCTest
@testable import LotusPlannerV3

final class TimeMathTests: XCTestCase {

    // MARK: - nextHalfHour(after:)

    func testNextHalfHour_BeforeHalf_RoundsToHalf() {
        let ref = makeDate(hour: 12, minute: 17)
        let result = TimeMath.nextHalfHour(after: ref)
        XCTAssertEqual(result.hour, 12)
        XCTAssertEqual(result.minute, 30)
    }

    func testNextHalfHour_AtHalf_RoundsToNextHour() {
        let ref = makeDate(hour: 12, minute: 30)
        let result = TimeMath.nextHalfHour(after: ref)
        XCTAssertEqual(result.hour, 13)
        XCTAssertEqual(result.minute, 0)
    }

    func testNextHalfHour_AfterHalf_RoundsToNextHour() {
        let ref = makeDate(hour: 12, minute: 45)
        let result = TimeMath.nextHalfHour(after: ref)
        XCTAssertEqual(result.hour, 13)
        XCTAssertEqual(result.minute, 0)
    }

    /// 23:45 + 30 min crosses midnight; next half-hour wraps to 0:00.
    /// Callers (BulkEditComponents) rely on the wrap to keep the
    /// hour valid; without it we'd produce hour=24 which then breaks
    /// `Calendar.date(bySettingHour:)`.
    func testNextHalfHour_LateNight_WrapsToMidnight() {
        let ref = makeDate(hour: 23, minute: 45)
        let result = TimeMath.nextHalfHour(after: ref)
        XCTAssertEqual(result.hour, 0)
        XCTAssertEqual(result.minute, 0)
    }

    func testNextHalfHour_AtTopOfHour_RoundsToHalf() {
        let ref = makeDate(hour: 9, minute: 0)
        let result = TimeMath.nextHalfHour(after: ref)
        XCTAssertEqual(result.hour, 9)
        XCTAssertEqual(result.minute, 30)
    }

    // MARK: - defaultTimedWindow(on:referenceTime:)

    func testDefaultTimedWindow_Duration_Is30Minutes() {
        let date = makeDate(year: 2026, month: 5, day: 10, hour: 0, minute: 0)
        let ref = makeDate(year: 2026, month: 5, day: 10, hour: 9, minute: 5)
        let window = TimeMath.defaultTimedWindow(on: date, referenceTime: ref)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 30 * 60)
    }

    /// Reference time anchors the hour/minute; the window's start must
    /// land on the target `date`'s calendar day, not the reference's.
    /// Required so a user editing a task whose due date is in the
    /// future still gets a sensible default time of day.
    func testDefaultTimedWindow_RebindsHourOntoTargetDate() {
        let target = makeDate(year: 2026, month: 5, day: 10, hour: 0, minute: 0)
        let reference = makeDate(year: 2026, month: 5, day: 8, hour: 14, minute: 22)
        let window = TimeMath.defaultTimedWindow(on: target, referenceTime: reference)

        let cal = Calendar.current
        XCTAssertTrue(cal.isDate(window.start, inSameDayAs: target),
                      "Window start should land on target date, not reference date")
        XCTAssertEqual(cal.component(.hour, from: window.start), 14)
        XCTAssertEqual(cal.component(.minute, from: window.start), 30)
    }

    func testDefaultEventDuration_IsThirtyMinutes() {
        XCTAssertEqual(TimeMath.defaultEventDuration, 30 * 60)
    }

    // MARK: - Helpers

    private func makeDate(year: Int = 2026, month: Int = 5, day: Int = 8,
                          hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}
