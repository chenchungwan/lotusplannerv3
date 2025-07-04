import SwiftUI

private enum TimelineInterval: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", quarter = "Quarter", year = "Year"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }
}

struct GoalsView: View {
    @State private var date = Date()
    @State private var interval: TimelineInterval = .day
    var body: some View {
        Text("Goals View")
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .sidebarToggleHidden()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { step(-1) }) { Image(systemName: "chevron.left") }
                    Button("Today") { date = Date() }
                    Button(action: { step(1) }) { Image(systemName: "chevron.right") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ForEach(TimelineInterval.allCases) { item in
                        Button(item.rawValue) { interval = item }
                            .fontWeight(item == interval ? .bold : .regular)
                    }
                }
            }
    }

    private func step(_ dir: Int) {
        if let newDate = Calendar.current.date(byAdding: interval.component, value: dir, to: date) {
            date = newDate
        }
    }
}

#Preview {
    GoalsView()
} 