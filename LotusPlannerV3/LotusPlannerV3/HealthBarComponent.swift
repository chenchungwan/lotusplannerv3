import SwiftUI
import HealthKit

/// A single reorderable/toggleable item in the Health Bar. The user's order
/// and per-item visibility live in `AppPreferences`; `HealthBarComponent`
/// reads both to decide what to render and in what sequence.
enum HealthBarItem: String, CaseIterable, Identifiable, Codable, Hashable {
    case sleep
    case weight
    case water
    case workoutStreak
    case workouts
    case activityRings
    case steps
    case activeEnergy
    case restingEnergy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep:          return "Sleep"
        case .weight:         return "Weight"
        case .water:          return "Water"
        case .workoutStreak:  return "Workout Streak"
        case .workouts:       return "Workouts"
        case .activityRings:  return "Activity Rings"
        case .steps:          return "Steps"
        case .activeEnergy:   return "Active Energy"
        case .restingEnergy:  return "Resting Energy"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep:          return "bed.double.fill"
        case .weight:         return "scalemass.fill"
        case .water:          return "drop.fill"
        case .workoutStreak:  return "trophy.fill"
        case .workouts:       return "figure.run"
        case .activityRings:  return "figure.walk.motion"
        case .steps:          return "shoeprints.fill"
        case .activeEnergy:   return "figure.arms.open"
        case .restingEnergy:  return "gauge.medium"
        }
    }

    /// Default order used for new users and to backfill any items the saved
    /// order is missing (so future additions appear automatically).
    static let defaultOrder: [HealthBarItem] = [
        .sleep, .weight, .water, .workoutStreak, .workouts, .activityRings,
        .steps, .activeEnergy, .restingEnergy
    ]
}

/// A one-line-tall horizontal bar summarizing the day's health data — sleep
/// times, weight, rolling workout streak, and each workout logged for the
/// day — for use as a top/bottom strip in the Custom Day View.
///
/// Content is left-aligned; if it exceeds the available width the user can
/// scroll horizontally to see the rest.
struct HealthBarComponent: View {
    let date: Date

    @ObservedObject private var logsVM = LogsViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var healthKit = HealthKitManager.shared

    var body: some View {
        // Wrap in a VStack with a trailing Spacer so the bar always pins to
        // the top of whatever cell it's dropped into — if the user merges
        // rows the extra height sits blank below the bar instead of
        // centering it.
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Render in the order the user set in Settings, skipping
                    // any items they've toggled off.
                    ForEach(appPrefs.healthBarOrder) { item in
                        if appPrefs.isHealthBarItemVisible(item) {
                            content(for: item)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .task(id: date) {
                await fetchActiveHealthKitMetrics()
            }
            .task(id: appPrefs.showActivityRings) {
                if appPrefs.showActivityRings { await healthKit.fetchActivityRings(for: date) }
            }
            .task(id: appPrefs.showHKSteps) {
                if appPrefs.showHKSteps { await healthKit.fetchSteps(for: date) }
            }
            .task(id: appPrefs.showHKActiveEnergy) {
                if appPrefs.showHKActiveEnergy { await healthKit.fetchActiveEnergy(for: date) }
            }
            .task(id: appPrefs.showHKRestingEnergy) {
                if appPrefs.showHKRestingEnergy { await healthKit.fetchRestingEnergy(for: date) }
            }
            .task(id: appPrefs.weightSource) {
                if appPrefs.weightSource == .appleHealth { await healthKit.fetchWeight(for: date) }
            }
            .task(id: appPrefs.workoutSource) {
                if appPrefs.workoutSource == .appleHealth { await healthKit.fetchWorkouts(for: date) }
            }

            Spacer(minLength: 0)
        }
    }

    /// Fires every active HealthKit fetch for the current date in parallel —
    /// triggered when `date` changes so each chip refreshes for the new day.
    private func fetchActiveHealthKitMetrics() async {
        await withTaskGroup(of: Void.self) { group in
            if appPrefs.showActivityRings { group.addTask { await healthKit.fetchActivityRings(for: date) } }
            if appPrefs.showHKSteps { group.addTask { await healthKit.fetchSteps(for: date) } }
            if appPrefs.showHKActiveEnergy { group.addTask { await healthKit.fetchActiveEnergy(for: date) } }
            if appPrefs.showHKRestingEnergy { group.addTask { await healthKit.fetchRestingEnergy(for: date) } }
            if appPrefs.weightSource == .appleHealth { group.addTask { await healthKit.fetchWeight(for: date) } }
            if appPrefs.workoutSource == .appleHealth { group.addTask { await healthKit.fetchWorkouts(for: date) } }
        }
    }

    @ViewBuilder
    private func content(for item: HealthBarItem) -> some View {
        switch item {
        case .sleep:          sleepChip
        case .weight:         weightChip
        case .water:          waterChip
        case .workoutStreak:  workoutStreakChip
        case .workouts:       workoutChips
        case .activityRings:  activityRingsChip
        case .steps:          stepsChip
        case .activeEnergy:   activeEnergyChip
        case .restingEnergy:  restingEnergyChip
        }
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepChip: some View {
        if let entry = logsVM.sleepLogs(on: date).last {
            chip(
                systemImage: "bed.double.fill",
                iconColor: .indigo,
                text: sleepText(entry: entry)
            )
        }
    }

    private func sleepText(entry: SleepLogEntry) -> String {
        let bed = entry.bedTime.map(Self.timeFormatter.string(from:)) ?? "—"
        let wake = entry.wakeUpTime.map(Self.timeFormatter.string(from:)) ?? "—"
        return "\(bed) → \(wake)"
    }

    // MARK: - Weight

    @ViewBuilder
    private var weightChip: some View {
        switch appPrefs.weightSource {
        case .app:
            // `weightLogs(on:)` returns entries sorted newest-first
            // (LogsViewModel.rebuildWeightCache uses `$0.timestamp > $1.timestamp`),
            // so .first is the newest entry. When a day has multiple weigh-ins
            // we collapse to that one rather than showing each.
            if let entry = logsVM.weightLogs(on: date).first {
                chip(
                    systemImage: "scalemass.fill",
                    iconColor: .teal,
                    text: "\(formattedWeight(entry.weight)) \(entry.unit.displayName)"
                )
            }
        case .appleHealth:
            if let metric = healthKit.weight(for: date) {
                let displayed = displayWeight(kilograms: metric.value)
                chip(
                    systemImage: "scalemass.fill",
                    iconColor: .teal,
                    text: displayed
                )
            }
        }
    }

    /// Renders the HK weight (always stored in kg) using the user's preferred
    /// in-app unit so the chip stays visually consistent regardless of source.
    private func displayWeight(kilograms: Double) -> String {
        let unit = logsVM.selectedWeightUnit
        let value: Double
        switch unit {
        case .pounds:
            value = kilograms * 2.2046226218
        case .kilograms:
            value = kilograms
        }
        return "\(formattedWeight(value)) \(unit.displayName)"
    }

    private func formattedWeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    // MARK: - Water

    /// One water-drop icon per cup logged for the day. Hides itself when
    /// zero cups, matching the other chips that self-hide without data.
    @ViewBuilder
    private var waterChip: some View {
        let cups = logsVM.waterLogs(on: date).reduce(0) { $0 + $1.cupsConsumed }
        if cups > 0 {
            HStack(spacing: 2) {
                ForEach(0..<cups, id: \.self) { _ in
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.systemBackground)))
            .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
        }
    }

    // MARK: - Workout streak

    /// Matches the trophy icon + color ramp used in `LogsComponent`'s
    /// workout section so the streak reads the same across the app.
    private var workoutStreakChip: some View {
        let streak = logsVM.workoutStreak(on: date)
        let color = streakColor(streak)
        return HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundColor(color)
            Text("\(streak)/7")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(.systemBackground)))
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    private func streakColor(_ streak: Int) -> Color {
        if streak >= 5 { return .green }
        if streak == 4 { return .teal }
        if streak > 0 { return .red }
        return .secondary
    }

    // MARK: - Workouts

    /// One chip per workout logged for the day. Source comes from the user's
    /// `workoutSource` preference: in-app `WorkoutLog` rows, or HealthKit
    /// `HKWorkout` samples (Apple Watch, third-party trackers, etc).
    @ViewBuilder
    private var workoutChips: some View {
        switch appPrefs.workoutSource {
        case .app:
            let workouts = logsVM.workoutLogs(on: date)
            ForEach(workouts) { workout in
                workoutChip(workout)
            }
        case .appleHealth:
            let workouts = healthKit.workouts(for: date)
            ForEach(workouts, id: \.uuid) { workout in
                hkWorkoutChip(workout)
            }
        }
    }

    private func workoutChip(_ workout: WorkoutLogEntry) -> some View {
        let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = appPrefs.colorForWorkoutType(workout.workoutType)
        return HStack(spacing: 4) {
            Image(systemName: workout.displayIcon)
                .font(.caption)
                .foregroundColor(color)
            if !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(.systemBackground)))
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    private func hkWorkoutChip(_ workout: HKWorkout) -> some View {
        // HKWorkoutActivityType doesn't map cleanly to our app's WorkoutType
        // enum, so use a generic running figure plus the duration as the
        // label. Could be enriched later with per-activity-type icons.
        let minutes = Int((workout.duration / 60).rounded())
        return HStack(spacing: 4) {
            Image(systemName: "figure.run")
                .font(.caption)
                .foregroundColor(.pink)
            Text("\(minutes) min")
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(.systemBackground)))
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    // MARK: - Steps / energy

    @ViewBuilder
    private var stepsChip: some View {
        if appPrefs.showHKSteps, let metric = healthKit.steps(for: date), metric.value > 0 {
            chip(
                systemImage: "shoeprints.fill",
                iconColor: .green,
                text: "\(Int(metric.value.rounded())) steps"
            )
        }
    }

    @ViewBuilder
    private var activeEnergyChip: some View {
        if appPrefs.showHKActiveEnergy, let metric = healthKit.activeEnergy(for: date), metric.value > 0 {
            chip(
                systemImage: "figure.arms.open",
                iconColor: .orange,
                text: "\(Int(metric.value.rounded())) calories active"
            )
        }
    }

    @ViewBuilder
    private var restingEnergyChip: some View {
        if appPrefs.showHKRestingEnergy, let metric = healthKit.restingEnergy(for: date), metric.value > 0 {
            chip(
                systemImage: "gauge.medium",
                iconColor: .indigo,
                text: "\(Int(metric.value.rounded())) calories resting"
            )
        }
    }

    // MARK: - Activity rings

    /// Apple Health Move / Exercise / Stand rings for the day. Only rendered
    /// when the user has activity rings enabled in Settings (they drive
    /// whether we prompt for HealthKit access at all).
    @ViewBuilder
    private var activityRingsChip: some View {
        if appPrefs.showActivityRings {
            let rings = healthKit.ringData(for: date)
            HStack(spacing: 5) {
                activityRing(value: rings.moveValue,    goal: rings.moveGoal,    color: .red)
                activityRing(value: rings.exerciseValue, goal: rings.exerciseGoal, color: .green)
                activityRing(value: rings.standValue,   goal: rings.standGoal,   color: .cyan)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.systemBackground)))
            .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
        }
    }

    private func activityRing(value: Double, goal: Double, color: Color) -> some View {
        let progress = goal > 0 ? min(value / goal, 1.0) : 0
        let isComplete = goal > 0 && value >= goal
        let size: CGFloat = 14
        return ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2.5)
                .frame(width: size, height: size)
            if isComplete {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Chip

    private func chip(systemImage: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(iconColor)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color(.systemBackground))
        )
        .overlay(
            Capsule().stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "a"
        formatter.pmSymbol = "p"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

#Preview {
    HealthBarComponent(date: Date())
        .frame(height: 32)
        .padding()
}
