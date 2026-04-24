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

    /// Lightweight per-day samples surfaced in the Health Bar chips.
    struct DailyMetric: Equatable {
        /// Numeric value in the type's native HK unit (kcal for energy, count
        /// for steps, kg for weight). The chip view formats the display.
        var value: Double
        /// Latest sample's wall-clock time on the day, when meaningful (e.g.
        /// most recent weight reading); nil for cumulative-only metrics like
        /// step count.
        var timestamp: Date?
    }

    /// Cached ring data keyed by normalized date
    @Published var ringDataByDay: [Date: ActivityRingData] = [:]
    /// Cached step counts (sum of HKQuantityTypeIdentifier.stepCount samples)
    @Published var stepsByDay: [Date: DailyMetric] = [:]
    /// Cached active energy burned (kcal sum)
    @Published var activeEnergyByDay: [Date: DailyMetric] = [:]
    /// Cached basal/resting energy burned (kcal sum)
    @Published var restingEnergyByDay: [Date: DailyMetric] = [:]
    /// Cached body mass — most-recent reading on the day in kg.
    @Published var weightByDay: [Date: DailyMetric] = [:]
    /// Cached HKWorkout list per day, sorted by start time ascending.
    @Published var workoutsByDay: [Date: [HKWorkout]] = [:]

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var hasRequestedAuth = false

    private init() {
        if isHealthKitAvailable {
            isAuthorized = AppPreferences.shared.showActivityRings
        }
    }

    /// Read-types we ask for. Bundled in one auth prompt so the user sees a
    /// single dialog covering every Health-backed chip the app can render.
    private var allReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.activitySummaryType()]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let active = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(active) }
        if let resting = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(resting) }
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async -> Bool {
        guard isHealthKitAvailable else { return false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
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

    // MARK: - Activity rings

    func ringData(for date: Date) -> ActivityRingData {
        let key = Calendar.current.startOfDay(for: date)
        return ringDataByDay[key] ?? ActivityRingData()
    }

    func fetchActivityRings(for date: Date) async {
        guard await primeAuthIfNeeded() else { return }

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
                    exerciseGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
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

    // MARK: - Steps / energy (cumulative per day)

    func steps(for date: Date) -> DailyMetric? {
        stepsByDay[Calendar.current.startOfDay(for: date)]
    }

    func activeEnergy(for date: Date) -> DailyMetric? {
        activeEnergyByDay[Calendar.current.startOfDay(for: date)]
    }

    func restingEnergy(for date: Date) -> DailyMetric? {
        restingEnergyByDay[Calendar.current.startOfDay(for: date)]
    }

    func fetchSteps(for date: Date) async {
        await fetchCumulativeQuantity(
            identifier: .stepCount,
            unit: .count(),
            date: date,
            cache: \.stepsByDay
        )
    }

    func fetchActiveEnergy(for date: Date) async {
        await fetchCumulativeQuantity(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            date: date,
            cache: \.activeEnergyByDay
        )
    }

    func fetchRestingEnergy(for date: Date) async {
        await fetchCumulativeQuantity(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            date: date,
            cache: \.restingEnergyByDay
        )
    }

    /// Sums every sample of the given quantity type on the given day and
    /// stores the total in the supplied cache.
    private func fetchCumulativeQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        date: Date,
        cache cachePath: ReferenceWritableKeyPath<HealthKitManager, [Date: DailyMetric]>
    ) async {
        guard await primeAuthIfNeeded(),
              let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

        do {
            let total: Double = try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: quantityType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error { continuation.resume(throwing: error); return }
                    let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                    continuation.resume(returning: value)
                }
                healthStore.execute(query)
            }
            self[keyPath: cachePath][dayStart] = DailyMetric(value: total, timestamp: nil)
        } catch {
            devLog("HealthKit \(identifier.rawValue) fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Weight (latest sample on the day)

    func weight(for date: Date) -> DailyMetric? {
        weightByDay[Calendar.current.startOfDay(for: date)]
    }

    func fetchWeight(for date: Date) async {
        guard await primeAuthIfNeeded(),
              let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: bodyMass,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(query)
            }

            if let latest = samples.first {
                let kg = latest.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                weightByDay[dayStart] = DailyMetric(value: kg, timestamp: latest.endDate)
            } else {
                weightByDay.removeValue(forKey: dayStart)
            }
        } catch {
            devLog("HealthKit weight fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Workouts

    func workouts(for date: Date) -> [HKWorkout] {
        workoutsByDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    func fetchWorkouts(for date: Date) async {
        guard await primeAuthIfNeeded() else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
                healthStore.execute(query)
            }
            workoutsByDay[dayStart] = workouts
        } catch {
            devLog("HealthKit workouts fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Auth helper

    /// Lazily requests auth on first call so individual fetch helpers don't
    /// each duplicate the gating logic.
    private func primeAuthIfNeeded() async -> Bool {
        if !hasRequestedAuth {
            hasRequestedAuth = true
            return await requestAuthorization()
        }
        return await ensureAuthorized()
    }
}
