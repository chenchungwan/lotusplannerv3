import Foundation
import HealthKit

@MainActor
class HealthManager: ObservableObject {
    static let shared = HealthManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var isHealthKitAvailable = HKHealthStore.isHealthDataAvailable()

    // MARK: - Published Data

    @Published var sleepData: DaySleepData?
    @Published var weightValue: Double?
    @Published var weightUnit: String = "lbs"
    @Published var weightEntries: [WeightEntry] = []
    @Published var workouts: [WorkoutData] = []
    @Published var steps: Int = 0
    @Published var activeCalories: Double = 0
    @Published var totalCalories: Double = 0
    @Published var moveGoal: Double = 0
    @Published var moveValue: Double = 0
    @Published var exerciseGoal: Double = 0
    @Published var exerciseValue: Double = 0
    @Published var standGoal: Double = 0
    @Published var standValue: Double = 0

    // MARK: - Data Models

    struct DaySleepData {
        let hours: Double
        let bedtime: Date?
        let wakeTime: Date?
    }

    struct WeightEntry: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
        let sample: HKQuantitySample?
    }

    struct WorkoutData: Identifiable {
        let id = UUID()
        let activityType: HKWorkoutActivityType
        let duration: TimeInterval
        let totalCalories: Double

        var activityName: String {
            switch activityType {
            case .running: return "Running"
            case .walking: return "Walking"
            case .cycling: return "Cycling"
            case .swimming: return "Swimming"
            case .hiking: return "Hiking"
            case .yoga: return "Yoga"
            case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
            case .highIntensityIntervalTraining: return "HIIT"
            case .dance: return "Dance"
            case .cooldown: return "Cooldown"
            case .coreTraining: return "Core"
            case .elliptical: return "Elliptical"
            case .rowing: return "Rowing"
            case .stairClimbing: return "Stairs"
            case .pilates: return "Pilates"
            case .crossTraining: return "Cross Training"
            case .mixedCardio: return "Cardio"
            case .jumpRope: return "Jump Rope"
            default: return "Workout"
            }
        }

        var icon: String {
            switch activityType {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .cycling: return "figure.outdoor.cycle"
            case .swimming: return "figure.pool.swim"
            case .hiking: return "figure.hiking"
            case .yoga: return "figure.yoga"
            case .functionalStrengthTraining, .traditionalStrengthTraining: return "dumbbell.fill"
            case .highIntensityIntervalTraining: return "bolt.heart.fill"
            case .dance: return "figure.dance"
            case .elliptical: return "figure.elliptical"
            case .rowing: return "figure.rower"
            case .stairClimbing: return "figure.stairs"
            case .pilates: return "figure.pilates"
            case .cooldown: return "figure.cooldown"
            case .coreTraining: return "figure.core.training"
            default: return "figure.mixed.cardio"
            }
        }
    }

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isHealthKitAvailable else { return }

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKObjectType.activitySummaryType(),
        ]

        let typesToShare: Set<HKSampleType> = [
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            isAuthorized = true
            devLog("HealthKit authorization granted", level: .info, category: .general)
        } catch {
            devLog("HealthKit authorization failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Fetch Data for a Day

    func fetchDayData(for date: Date) async {
        guard isHealthKitAvailable, isAuthorized else { return }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        async let sleepTask: () = fetchSleep(start: start, end: end)
        async let weightTask: () = fetchWeight(start: start, end: end)
        async let workoutTask: () = fetchWorkouts(start: start, end: end)
        async let stepsTask: () = fetchSteps(start: start, end: end)
        async let energyTask: () = fetchEnergy(start: start, end: end)
        async let ringsTask: () = fetchActivityRings(for: date)

        _ = await (sleepTask, weightTask, workoutTask, stepsTask, energyTask, ringsTask)
    }

    // MARK: - Sleep

    private func fetchSleep(start: Date, end: Date) async {
        let sleepType = HKCategoryType(.sleepAnalysis)
        // Look back to 6 PM the previous day to capture overnight sleep sessions
        // that started the evening before (e.g., 11 PM → 7 AM)
        let calendar = Calendar.current
        let sleepStart = calendar.date(byAdding: .hour, value: -6, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: sleepStart, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results as? [HKCategorySample] ?? [])
                }
                healthStore.execute(query)
            }

            var totalHours: Double = 0
            var earliest: Date?
            var latest: Date?

            for sample in samples {
                let v = sample.value
                guard v == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                      v == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                      v == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                      v == HKCategoryValueSleepAnalysis.asleepREM.rawValue else { continue }

                totalHours += sample.endDate.timeIntervalSince(sample.startDate) / 3600.0

                if earliest == nil || sample.startDate < earliest! { earliest = sample.startDate }
                if latest == nil || sample.endDate > latest! { latest = sample.endDate }
            }

            sleepData = totalHours > 0 ? DaySleepData(hours: totalHours, bedtime: earliest, wakeTime: latest) : nil
        } catch {
            devLog("HealthKit sleep fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Weight

    private func fetchWeight(start: Date, end: Date) async {
        let weightType = HKQuantityType(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                }
                healthStore.execute(query)
            }

            let unit = HKUnit.pound()
            weightValue = samples.first?.quantity.doubleValue(for: unit)
            weightEntries = samples.map { sample in
                WeightEntry(date: sample.startDate, weight: sample.quantity.doubleValue(for: unit), sample: sample)
            }.sorted { $0.date < $1.date }
        } catch {
            devLog("HealthKit weight fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Workouts

    private func fetchWorkouts(start: Date, end: Date) async {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let samples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results as? [HKWorkout] ?? [])
                }
                healthStore.execute(query)
            }

            workouts = samples.map { w in
                WorkoutData(
                    activityType: w.workoutActivityType,
                    duration: w.duration,
                    totalCalories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
                )
            }
        } catch {
            devLog("HealthKit workout fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Steps

    private func fetchSteps(start: Date, end: Date) async {
        let stepsType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            let result: Double = try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                }
                healthStore.execute(query)
            }
            steps = Int(result)
        } catch {
            devLog("HealthKit steps fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Energy

    private func fetchEnergy(start: Date, end: Date) async {
        let activeType = HKQuantityType(.activeEnergyBurned)
        let basalType = HKQuantityType(.basalEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let activeResult: Double = withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: activeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            healthStore.execute(query)
        }

        async let basalResult: Double = withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: basalType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            healthStore.execute(query)
        }

        do {
            let active = try await activeResult
            let basal = try await basalResult
            activeCalories = active
            totalCalories = active + basal
        } catch {
            devLog("HealthKit energy fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Activity Rings

    private func fetchActivityRings(for date: Date) async {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day, .era], from: date)
        dateComponents.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

        do {
            let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { continuation in
                let query = HKActivitySummaryQuery(predicate: predicate) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results ?? [])
                }
                healthStore.execute(query)
            }

            if let summary = summaries.first {
                moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                moveValue = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
                exerciseValue = summary.appleExerciseTime.doubleValue(for: .minute())
                standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())
                standValue = summary.appleStandHours.doubleValue(for: .count())
            } else {
                moveGoal = 0; moveValue = 0
                exerciseGoal = 0; exerciseValue = 0
                standGoal = 0; standValue = 0
            }
        } catch {
            devLog("HealthKit activity rings fetch failed: \(error)", level: .error, category: .general)
        }
    }

    // MARK: - Write Weight to HealthKit

    func saveWeight(_ value: Double, unit: HKUnit = .pound(), date: Date) async throws {
        let weightType = HKQuantityType(.bodyMass)
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: weightType, quantity: quantity, start: date, end: date)
        try await healthStore.save(sample)
    }

    func deleteWeight(_ entry: WeightEntry) async throws {
        // Query for samples at this exact date to get a fresh reference owned by this app
        let weightType = HKQuantityType(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: entry.date, end: entry.date.addingTimeInterval(1), options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }

        let unit = HKUnit.pound()
        // Find the matching sample by weight value
        if let match = samples.first(where: { abs($0.quantity.doubleValue(for: unit) - entry.weight) < 0.1 }) {
            try await healthStore.delete(match)
            devLog("Deleted weight entry from HealthKit", level: .info, category: .general)
        } else {
            devLog("Cannot delete weight: no matching sample found in HealthKit", level: .error, category: .general)
        }
    }

    // MARK: - Weight Reconciliation

    /// Fetches all HealthKit weight entries for a given day range and reconciles with app data.
    /// Rules:
    /// - App has data, HealthKit doesn't for that timestamp → write to HealthKit, delete from app
    /// - Both have same weight → delete from app
    /// - Both have different weight → add app data to HealthKit, delete from app
    func reconcileWeightData(appEntries: [WeightLogEntry], onDelete: @escaping (WeightLogEntry) -> Void) async {
        guard isHealthKitAvailable, isAuthorized else { return }
        guard !appEntries.isEmpty else { return }

        // Fetch all HealthKit weight samples covering the date range of app entries
        let calendar = Calendar.current
        let dates = appEntries.map { $0.timestamp }
        guard let earliest = dates.min(), let latest = dates.max() else { return }
        let start = calendar.startOfDay(for: earliest)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest))!

        let weightType = HKQuantityType(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            let hkSamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                }
                healthStore.execute(query)
            }

            for appEntry in appEntries {
                let appWeightInLbs: Double
                switch appEntry.unit {
                case .pounds:
                    appWeightInLbs = appEntry.weight
                case .kilograms:
                    appWeightInLbs = appEntry.weight * 2.20462
                }

                // Find HealthKit entries on the same day
                let appDay = calendar.startOfDay(for: appEntry.timestamp)
                let matchingSamples = hkSamples.filter { calendar.startOfDay(for: $0.startDate) == appDay }

                if matchingSamples.isEmpty {
                    // No HealthKit data for this day → write app data to HealthKit
                    do {
                        try await saveWeight(appWeightInLbs, date: appEntry.timestamp)
                        devLog("Reconcile: wrote app weight \(appEntry.weight) to HealthKit for \(appEntry.timestamp)", level: .info, category: .general)
                    } catch {
                        devLog("Reconcile: failed to write weight to HealthKit: \(error)", level: .error, category: .general)
                        continue // Don't delete if write failed
                    }
                } else {
                    // Check if any HealthKit sample has the same weight (within 0.1 lbs tolerance)
                    let hasMatch = matchingSamples.contains { sample in
                        let hkWeight = sample.quantity.doubleValue(for: .pound())
                        return abs(hkWeight - appWeightInLbs) < 0.1
                    }

                    if !hasMatch {
                        // Different weight → add app data to HealthKit
                        do {
                            try await saveWeight(appWeightInLbs, date: appEntry.timestamp)
                            devLog("Reconcile: added different app weight \(appEntry.weight) to HealthKit for \(appEntry.timestamp)", level: .info, category: .general)
                        } catch {
                            devLog("Reconcile: failed to write weight to HealthKit: \(error)", level: .error, category: .general)
                            continue
                        }
                    }
                    // If same weight, just delete from app (handled below)
                }

                // Delete from app storage
                await MainActor.run {
                    onDelete(appEntry)
                }
            }
        } catch {
            devLog("Reconcile: failed to fetch HealthKit weight data: \(error)", level: .error, category: .general)
        }
    }
}
