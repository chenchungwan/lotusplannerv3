import SwiftUI

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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep:          return "Sleep"
        case .weight:         return "Weight"
        case .water:          return "Water"
        case .workoutStreak:  return "Workout Streak"
        case .workouts:       return "Workouts"
        case .activityRings:  return "Activity Rings"
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
        }
    }

    /// Default order used for new users and to backfill any items the saved
    /// order is missing (so future additions appear automatically).
    static let defaultOrder: [HealthBarItem] = [
        .sleep, .weight, .water, .workoutStreak, .workouts, .activityRings
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
            .background(Color(.secondarySystemBackground))
            .task(id: date) {
                guard appPrefs.showActivityRings else { return }
                await healthKit.fetchActivityRings(for: date)
            }
            .task(id: appPrefs.showActivityRings) {
                guard appPrefs.showActivityRings else { return }
                await healthKit.fetchActivityRings(for: date)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func content(for item: HealthBarItem) -> some View {
        switch item {
        case .sleep:         sleepChip
        case .weight:        weightChip
        case .water:         waterChip
        case .workoutStreak: workoutStreakChip
        case .workouts:      workoutChips
        case .activityRings: activityRingsChip
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
        if let entry = logsVM.weightLogs(on: date).last {
            chip(
                systemImage: "scalemass.fill",
                iconColor: .teal,
                text: "\(formattedWeight(entry.weight)) \(entry.unit.displayName)"
            )
        }
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

    /// One chip per workout logged for the day. Shows the workout-type icon;
    /// if the user entered a description (`name`) it's appended as text,
    /// otherwise the chip is icon-only.
    @ViewBuilder
    private var workoutChips: some View {
        let workouts = logsVM.workoutLogs(on: date)
        ForEach(workouts) { workout in
            workoutChip(workout)
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
