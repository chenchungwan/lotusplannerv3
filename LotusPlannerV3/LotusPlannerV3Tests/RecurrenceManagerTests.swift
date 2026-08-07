//
//  RecurrenceManagerTests.swift
//  LotusPlannerV3Tests
//
//  Tests for the recurrence rule data model. The library is the
//  source of truth for "what's the next due date" math; a regression
//  in encoding/decoding here would silently lose user-configured
//  recurrences across an app launch.
//

import XCTest
@testable import LotusPlannerV3

final class RecurrenceManagerTests: XCTestCase {

    // MARK: - RecurrenceFrequency

    func testFrequencyDisplayNames_AreHumanReadable() {
        XCTAssertEqual(RecurrenceFrequency.daily.displayName, "Daily")
        XCTAssertEqual(RecurrenceFrequency.weekly.displayName, "Weekly")
        XCTAssertEqual(RecurrenceFrequency.monthly.displayName, "Monthly")
        XCTAssertEqual(RecurrenceFrequency.yearly.displayName, "Yearly")
    }

    func testFrequencyUnitNames_AreSingular() {
        XCTAssertEqual(RecurrenceFrequency.daily.unitName, "day")
        XCTAssertEqual(RecurrenceFrequency.weekly.unitName, "week")
        XCTAssertEqual(RecurrenceFrequency.monthly.unitName, "month")
        XCTAssertEqual(RecurrenceFrequency.yearly.unitName, "year")
    }

    func testFrequencyRawValues_StableForJSON() {
        // These values land in JSON via Codable; renaming a case
        // would silently invalidate persisted rules. Test pinning
        // the raw values catches that.
        XCTAssertEqual(RecurrenceFrequency.daily.rawValue, "daily")
        XCTAssertEqual(RecurrenceFrequency.weekly.rawValue, "weekly")
        XCTAssertEqual(RecurrenceFrequency.monthly.rawValue, "monthly")
        XCTAssertEqual(RecurrenceFrequency.yearly.rawValue, "yearly")
    }

    // MARK: - RecurrenceRule round-trip

    func testRule_RoundTripsThroughJSON() throws {
        let rule = makeRule(
            currentTaskId: "task-abc",
            frequency: .weekly,
            interval: 2,
            endDate: nil,
            endCount: 8
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        XCTAssertEqual(decoded, rule)
    }

    func testRule_AccountKindEnum_DerivedFromString() {
        let account1 = makeRule(currentTaskId: "x", accountKind: "personal")
        let account2 = makeRule(currentTaskId: "x", accountKind: "professional")
        XCTAssertEqual(account1.accountKindEnum, .account1)
        XCTAssertEqual(account2.accountKindEnum, .account2)
    }

    /// Anything not literally "professional" maps to account 1 — matches
    /// the production fall-through logic. Verifies a corrupted-JSON
    /// edge case doesn't crash the manager.
    func testRule_AccountKindEnum_UnknownStringMapsToAccount1() {
        let unknown = makeRule(currentTaskId: "x", accountKind: "garbage")
        XCTAssertEqual(unknown.accountKindEnum, .account1)
    }

    // MARK: - RecurrenceLibrary

    func testLibrary_Empty_HasNoRules() {
        let lib = RecurrenceLibrary.empty()
        XCTAssertTrue(lib.rules.isEmpty)
    }

    func testLibrary_RoundTripsThroughJSON() throws {
        let rule1 = makeRule(currentTaskId: "task-1", frequency: .daily, interval: 1)
        let rule2 = makeRule(currentTaskId: "task-2", frequency: .monthly, interval: 3)
        let lib = RecurrenceLibrary(rules: [
            rule1.currentTaskId: rule1,
            rule2.currentTaskId: rule2
        ])

        let data = try JSONEncoder().encode(lib)
        let decoded = try JSONDecoder().decode(RecurrenceLibrary.self, from: data)

        XCTAssertEqual(decoded.rules.count, 2)
        XCTAssertEqual(decoded.rules["task-1"], rule1)
        XCTAssertEqual(decoded.rules["task-2"], rule2)
    }

    // MARK: - Helpers

    private func makeRule(
        currentTaskId: String,
        accountKind: String = "personal",
        frequency: RecurrenceFrequency = .weekly,
        interval: Int = 1,
        endDate: Date? = nil,
        endCount: Int? = nil
    ) -> RecurrenceRule {
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // fixed to keep equality stable
        return RecurrenceRule(
            seriesId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentTaskId: currentTaskId,
            accountKind: accountKind,
            listId: "list-1",
            frequency: frequency,
            interval: interval,
            endDate: endDate,
            endCount: endCount,
            occurrencesSpawned: 0,
            lastSpawnedDate: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
