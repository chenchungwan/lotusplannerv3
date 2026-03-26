import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false

    struct ActivityRingData {
        var moveGoal: Double = 0
        var moveValue: Double = 0
        var exerciseGoal: Double = 0
        var exerciseValue: Double = 0
        var standGoal: Double = 0
        var standValue: Double = 0
    }

    /// Cached ring data keyed by normalized date
    @Published var ringDataByDay: [Date: ActivityRingData] = [:]

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {
        if isHealthKitAvailable {
            isAuthorized = AppPreferences.shared.showActivityRings
        }
    }

    func requestAuthorization() async -> Bool {
        guard isHealthKitAvailable else { return false }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.activitySummaryType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            return true
        } catch {
            devLog("HealthKit authorization failed: \(error)", level: .error, category: .general)
            isAuthorized = false
            return false
        }
    }

    func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }
        return await requestAuthorization()
    }

    func ringData(for date: Date) -> ActivityRingData {
        let key = Calendar.current.startOfDay(for: date)
        return ringDataByDay[key] ?? ActivityRingData()
    }

    func fetchActivityRings(for date: Date) async {
        if !isAuthorized {
            let authorized = await ensureAuthorized()
            guard authorized else { return }
        }

        let calendar = Calendar.current
        let key = calendar.startOfDay(for: date)

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: components)

        do {
            let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { continuation in
                let query = HKActivitySummaryQuery(predicate: predicate) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results ?? [])
                }
                healthStore.execute(query)
            }

            if let summary = summaries.first {
                ringDataByDay[key] = ActivityRingData(
                    moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    moveValue: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseGoal: summary.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseValue: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standGoal: summary.appleStandHoursGoal.doubleValue(for: .count()),
                    standValue: summary.appleStandHours.doubleValue(for: .count())
                )
            } else {
                ringDataByDay[key] = ActivityRingData()
            }
        } catch {
            devLog("HealthKit activity rings fetch failed: \(error)", level: .error, category: .general)
        }
    }
}
