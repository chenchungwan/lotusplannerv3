import SwiftUI
import Charts

/// Line chart of the user's logged weight over a selectable range (week,
/// month, or year) containing `currentDate`. Uses the same header + menu
/// dropdown pattern as the Goals picker component so the day view's
/// configurable panels read consistently.
struct WeightGraphComponent: View {
    let currentDate: Date
    /// When non-nil, the chart is pinned to this range and the picker is
    /// hidden — the header shows the period label directly (e.g.
    /// "Weight WK17: 4/20 - 4/26"), matching the Goals components.
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

            if dataPoints.isEmpty {
                emptyState
            } else {
                chart
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

            // Unit pill — lets the user see what units they're reading without
            // overloading the chart's axis labels.
            if !dataPoints.isEmpty {
                Text(displayUnit.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
        }
    }

    /// When a fixed timeframe is set, embed the period label into the title
    /// (e.g. "Weight April"); otherwise the picker conveys the range.
    private var titleText: String {
        if let fixed = fixedTimeframe {
            return "Weight \(GoalsTimeframeHeaderFormatter.periodLabel(for: fixed, on: currentDate))"
        }
        return "Weight"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No weight entries in this \(activeTimeframe.displayName.lowercased()).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var chart: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weight)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weight)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(24)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis { xAxisContent }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        switch activeTimeframe {
        case .week:
            // One tick per day, short weekday label (M/T/W/T/F/S/S).
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        case .month:
            // One tick per week with day-of-month to keep labels readable.
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        case .year:
            // One tick per month, abbreviated month label.
            AxisMarks(values: .stride(by: .month, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.narrow))
            }
        }
    }

    // MARK: - Data

    /// Start / end of the selected period containing `currentDate`. Uses the
    /// Monday-first calendar to align with the rest of the app.
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
        // Chart looks cleanest with an inclusive-end domain; subtract a
        // second so the range reads as "through end of last day".
        return r.start...r.end.addingTimeInterval(-1)
    }

    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.weight }
        guard let min = values.min(), let max = values.max() else {
            return 0...1
        }
        let padding = max == min ? 1 : (max - min) * 0.15
        return (min - padding)...(max + padding)
    }

    /// The weight unit used for the y-axis — inferred from the most recent
    /// entry in the range so the graph reads in whatever the user most
    /// recently logged. Defaults to pounds if the range is empty (but then
    /// we render the empty state anyway).
    private var displayUnit: WeightUnit {
        entriesInRange.sorted { $0.timestamp > $1.timestamp }.first?.unit ?? .pounds
    }

    /// Entries whose `date` falls in the selected period, sorted ascending
    /// by timestamp so the line chart reads left-to-right in time.
    private var entriesInRange: [WeightLogEntry] {
        let r = dateRange
        return logsVM.weightEntries
            .filter { $0.date >= r.start && $0.date < r.end }
    }

    /// One data point per entry, with each weight converted into
    /// `displayUnit` so a line connecting mixed-unit entries still reads as
    /// one consistent series.
    private var dataPoints: [WeightDataPoint] {
        let unit = displayUnit
        return entriesInRange
            .sorted { $0.timestamp < $1.timestamp }
            .map { WeightDataPoint(date: $0.timestamp, weight: Self.convert($0.weight, from: $0.unit, to: unit)) }
    }

    /// Converts between pounds and kilograms. Same factor used throughout
    /// the app (1 kg ≈ 2.20462 lbs).
    private static func convert(_ value: Double, from: WeightUnit, to: WeightUnit) -> Double {
        if from == to { return value }
        switch (from, to) {
        case (.pounds, .kilograms): return value / 2.20462
        case (.kilograms, .pounds): return value * 2.20462
        default: return value
        }
    }
}

/// Plain value-type for Charts — using `timestamp` (not day-normalized
/// date) as the id and x so multiple entries on the same day each get
/// their own data point.
private struct WeightDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

#Preview {
    WeightGraphComponent(currentDate: Date())
        .frame(width: 360, height: 260)
}
