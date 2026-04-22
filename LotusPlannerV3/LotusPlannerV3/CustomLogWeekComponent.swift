import SwiftUI

/// Weekly-grid variant of the custom log component. Rows are custom log
/// items, columns are the seven days of the week containing `currentDate`
/// (Mon–Sun). Each cell is a tappable circle that toggles that item's
/// completion for that day.
struct CustomLogWeekComponent: View {
    let currentDate: Date

    @ObservedObject private var manager = CustomLogManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    private let dayColumnWidth: CGFloat = 28
    private let titleColumnWidth: CGFloat = 140

    /// Total intrinsic width of the grid: item title column plus seven day
    /// columns. Used so the outer horizontal ScrollView can show scroll
    /// indicators / allow the user to pan when the cell is narrower than
    /// this.
    private var contentWidth: CGFloat {
        titleColumnWidth + dayColumnWidth * 7
    }

    /// The seven days (Monday → Sunday) of the week containing `currentDate`.
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: currentDate) else {
            return []
        }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    private var enabledItems: [CustomLogItemData] {
        manager.items.filter { $0.isEnabled }
    }

    var body: some View {
        // Single ScrollView covering both axes: horizontal lets the user pan
        // when the cell isn't wide enough for the title + 7 day columns;
        // vertical lets them scroll through more items than fit vertically.
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Divider()
                    .frame(width: contentWidth)
                if enabledItems.isEmpty {
                    Text("No custom log items. Add some in Settings → Custom Logs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(enabledItems) { item in
                        itemRow(item)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .topLeading)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            // Placeholder to align day labels with the check columns below.
            Color.clear
                .frame(width: titleColumnWidth, height: 1)
            HStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                    Text(weekdayInitial(index: index))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(isToday(date) ? .accentColor : .secondary)
                        .frame(width: dayColumnWidth, alignment: .center)
                }
            }
        }
    }

    // MARK: - Row

    private func itemRow(_ item: CustomLogItemData) -> some View {
        HStack(spacing: 0) {
            Text(item.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: titleColumnWidth, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.offset) { _, date in
                    checkCell(itemId: item.id, date: date)
                        .frame(width: dayColumnWidth, alignment: .center)
                }
            }
        }
    }

    private func checkCell(itemId: UUID, date: Date) -> some View {
        let isChecked = manager.getCompletionStatus(for: itemId, date: date)
        return Button {
            manager.toggleEntry(for: itemId, date: date)
        } label: {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundColor(isChecked ? .accentColor : .secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Weekday initial for a Monday-first layout: M T W T F S S.
    private func weekdayInitial(index: Int) -> String {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        guard letters.indices.contains(index) else { return "" }
        return letters[index]
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
}

#Preview {
    CustomLogWeekComponent(currentDate: Date())
        .frame(width: 320, height: 260)
}
