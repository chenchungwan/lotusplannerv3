import SwiftUI

// MARK: - Goals Summary View
struct GoalsSummaryView: View {
    let completed: Int
    let total: Int
    let currentInterval: TimelineInterval
    let currentDate: Date
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var completionPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    private var timeframeTitle: String {
        let formatter = DateFormatter()
        
        switch currentInterval {
        case .week:
            formatter.dateFormat = "MMM d"
            let startOfWeek = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let endOfWeek = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: startOfWeek) ?? currentDate
            return "Week of \(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: currentDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: currentDate)
        case .day:
            return "All Goals"
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 20
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    var body: some View {
        VStack(spacing: adaptiveSpacing) {
            // Timeframe title
            Text(timeframeTitle)
                .font(horizontalSizeClass == .compact ? .subheadline : .headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Progress bar and stats
            HStack(spacing: 12) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 8)
                            .fill(completionPercentage == 1.0 ? Color.green : Color.blue)
                            .frame(width: geometry.size.width * completionPercentage, height: horizontalSizeClass == .compact ? 12 : 16)
                            .animation(.easeInOut(duration: 0.3), value: completionPercentage)
                    }
                }
                .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                
                // Stats text
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    
                    Text("\(completed)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("/")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(total)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(minWidth: horizontalSizeClass == .compact ? 60 : 80)
            }
            
            // Completion percentage
            if total > 0 {
                Text("\(Int(completionPercentage * 100))% Complete")
                    .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, horizontalSizeClass == .compact ? 12 : 16)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

