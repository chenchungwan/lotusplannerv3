import SwiftUI

struct HealthStatusBar: View {
    @ObservedObject private var healthManager = HealthManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var logsViewModel = LogsViewModel.shared

    private var currentDate: Date { navigationManager.currentDate }

    private var isFutureDate: Bool {
        Calendar.current.startOfDay(for: currentDate) > Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        if appPrefs.healthKitEnabled {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if isFutureDate {
                        // Future dates: only show workout streak
                        if appPrefs.showWorkoutStreak {
                            let streak = logsViewModel.workoutStreak(on: currentDate)
                            statusItem(
                                icon: "trophy.fill",
                                color: streakColor(streak),
                                value: "\(streak)/7"
                            )
                        }
                    } else if !healthManager.isAuthorized {
                        Label("Tap to enable Health access", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !hasData {
                        Label("No health data for this day", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // Sleep: bedtime - wake time (duration)
                        if let sleep = healthManager.sleepData {
                            statusItem(
                                icon: "bed.double.fill",
                                color: .indigo,
                                value: sleepText(sleep)
                            )
                        }

                        // Weight
                        if let weight = healthManager.weightValue {
                            statusItem(
                                icon: "scalemass.fill",
                                color: .blue,
                                value: String(format: "%.1f %@", weight, healthManager.weightUnit)
                            )
                        }

                        // Workout Streak
                        if appPrefs.showWorkoutStreak {
                            let streak = logsViewModel.workoutStreak(on: currentDate)
                            statusItem(
                                icon: "trophy.fill",
                                color: streakColor(streak),
                                value: "\(streak)/7"
                            )
                        }

                        // Workouts
                        ForEach(healthManager.workouts) { workout in
                            statusItem(
                                icon: workout.icon,
                                color: .orange,
                                value: "\(workout.activityName) \(formatDuration(workout.duration))"
                            )
                        }

                        // Steps
                        if healthManager.steps > 0 {
                            statusItem(
                                icon: "shoeprints.fill",
                                color: .green,
                                value: healthManager.steps.formatted()
                            )
                        }

                        // Active energy
                        if healthManager.activeCalories > 0 {
                            statusItem(
                                icon: "flame.fill",
                                color: .orange,
                                value: "\(Int(healthManager.activeCalories)) kcal"
                            )
                        }

                        // Total energy
                        if healthManager.totalCalories > 0 {
                            statusItem(
                                icon: "bolt.fill",
                                color: .purple,
                                value: "\(Int(healthManager.totalCalories)) kcal"
                            )
                        }

                        // Activity Rings: Move, Exercise, Stand
                        if healthManager.moveGoal > 0 {
                            activityRing(
                                value: healthManager.moveValue,
                                goal: healthManager.moveGoal,
                                color: .red,
                                unit: "kcal"
                            )
                        }

                        if healthManager.exerciseGoal > 0 {
                            activityRing(
                                value: healthManager.exerciseValue,
                                goal: healthManager.exerciseGoal,
                                color: .green,
                                unit: "min"
                            )
                        }

                        if healthManager.standGoal > 0 {
                            activityRing(
                                value: healthManager.standValue,
                                goal: healthManager.standGoal,
                                color: .cyan,
                                unit: "hr"
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(.systemGray6))
            .task(id: appPrefs.healthKitEnabled) {
                if !healthManager.isAuthorized {
                    await healthManager.requestAuthorization()
                }
                if healthManager.isAuthorized {
                    await healthManager.fetchDayData(for: currentDate)
                    await logsViewModel.reconcileWeightWithHealthKit()
                }
            }
            .task(id: currentDate) {
                guard healthManager.isAuthorized, !isFutureDate else { return }
                await healthManager.fetchDayData(for: currentDate)
            }
        }
    }

    // MARK: - Helpers

    private var hasData: Bool {
        healthManager.sleepData != nil ||
        healthManager.weightValue != nil ||
        !healthManager.workouts.isEmpty ||
        healthManager.steps > 0 ||
        healthManager.activeCalories > 0 ||
        healthManager.moveGoal > 0
    }

    private func statusItem(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    private func activityRing(value: Double, goal: Double, color: Color, unit: String) -> some View {
        let progress = min(value / goal, 1.0)
        let isComplete = value >= goal
        return HStack(spacing: 4) {
            ZStack {
                if isComplete {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                } else {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 3)
                        .frame(width: 16, height: 16)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(-90))
                }
            }
            Text("\(Int(value))/\(Int(goal)) \(unit)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    private func sleepText(_ sleep: HealthManager.DaySleepData) -> String {
        let h = Int(sleep.hours)
        let m = Int((sleep.hours - Double(h)) * 60)
        let duration = "\(h)h \(m)m"

        if let bed = sleep.bedtime, let wake = sleep.wakeTime {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return "\(fmt.string(from: bed)) – \(fmt.string(from: wake)) (\(duration))"
        }
        return duration
    }

    private func streakColor(_ streak: Int) -> Color {
        if streak >= 5 { return .green }
        if streak == 4 { return .teal }
        if streak > 0 { return .red }
        return .gray
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
