import SwiftUI
import Charts

/// Line chart of the user's rolling 7-day workout streak (0–7) over a
/// selectable range (week, month, or year) containing `currentDate`. Same
/// header + menu-dropdown pattern as the Weight and Goals picker
/// components so the Custom Day View's graphs read consistently.
///
/// When `fixedTimeframe` is provided the picker is hidden and the title
/// includes the period label (e.g. "Workout Streak WK17: 4/20 - 4/26").
struct WorkoutStreakGraphComponent: View {
    let currentDate: Date
    /// When non-nil, the chart is pinned to this range and the picker is
    /// hidden — the header shows the period label directly.
    let fixedTimeframe: GoalTimeframe?

    @ObservedObject private var logsVM = LogsViewModel.shared
    @State private var pickerSelection: GoalTimeframe = .week

    init(currentDate: Date, fixedTimeframe: GoalTimeframe? = nil) {
        self.currentDate = currentDate
        self.fixedTimeframe = fixedTimeframe
    }

    private var activeTimeframe: GoalTimeframe {
        fixedTimeframe ?? pickerSelection
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if hasAnyStreak {
                chart
            } else {
                emptyState
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(titleText)
                .font(.subheadline)
                .fontWeight(.semibold)

            if fixedTimeframe == nil {
                Picker("Timeframe", selection: $pickerSelection) {
                    Text("Week").tag(GoalTimeframe.week)
                    Text("Month").tag(GoalTimeframe.month)
                    Text("Year").tag(GoalTimeframe.year)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)
            }

            Spacer()
        }
    }

    private var titleText: String {
        if let fixed = fixedTimeframe {
            return "Workout Streak \(GoalsTimeframeHeaderFormatter.periodLabel(for: fixed, on: currentDate))"
        }
        return "Workout Streak"
    }

    private var emptyState: some View {
        Text("No workout streak to show in this \(activeTimeframe.displayName.lowercased()).")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private var chart: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Streak", point.streak)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Streak", point.streak)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(24)
            }
        }
        .chartXScale(domain: xDomain)
        // Streak is 0–7 by definition; freeze the y-scale so visually the
        // trend is comparable across days/weeks/years.
        .chartYScale(domain: 0...7)
        .chartXAxis { xAxisContent }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 2, 4, 6, 7])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        switch activeTimeframe {
        case .week:
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        case .year:
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.narrow))
            }
        }
    }

    // MARK: - Data

    /// Every day in the selected period, with that day's rolling 7-day
    /// streak value computed via `LogsViewModel.workoutStreak(on:)`.
    private var dataPoints: [StreakDataPoint] {
        let calendar = Calendar.current
        let range = dateRange
        var result: [StreakDataPoint] = []
        var day = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        while day < end {
            result.append(StreakDataPoint(date: day, streak: logsVM.workoutStreak(on: day)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Hides the chart in favor of an empty state when every sampled day
    /// in the range has a zero streak — a flat line at 0 is harder to
    /// interpret than a short text message.
    private var hasAnyStreak: Bool {
        dataPoints.contains { $0.streak > 0 }
    }

    /// Start / end of the selected period containing `currentDate`. Uses
    /// the Monday-first calendar so the week aligns with the rest of the app.
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.mondayFirst
        switch activeTimeframe {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: currentDate)
            let start = interval?.start ?? currentDate
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (start, calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: currentDate)
            return (interval?.start ?? currentDate, interval?.end ?? currentDate)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: currentDate)
            return (interval?.start ?? currentDate, interval?.end ?? currentDate)
        }
    }

    private var xDomain: ClosedRange<Date> {
        let r = dateRange
        return r.start...r.end.addingTimeInterval(-1)
    }
}

private struct StreakDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let streak: Int
}

#Preview {
    WorkoutStreakGraphComponent(currentDate: Date())
        .frame(width: 360, height: 260)
}
