import SwiftUI

/// Per-log-type column and card rendering for the W view: built-in visibility check, log row builder, weight/workout/food/water/custom log columns and per-entry cards. Tightly scoped to log rendering — task and scroll helpers live elsewhere.
extension WeeklyView {

    func isBuiltInLogVisible(_ logType: BuiltInLogType) -> Bool {
        switch logType {
        case .food: return appPrefs.showFoodLogs
        case .sleep: return appPrefs.showSleepLogs
        case .water: return appPrefs.showWaterLogs
        case .weight: return appPrefs.showWeightLogs
        case .workout: return appPrefs.showWorkoutLogs
        }
    }

    /// Renders a single custom-log collection row across the seven day
    /// columns. Mirrors the body of the legacy inline `.custom` case so
    /// adding `.custom2` could share the same layout.
    @ViewBuilder
    func customLogRow(collectionIndex: Int, dayColumnWidth: CGFloat, fixedWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    weekCustomLogColumn(date: date, collectionIndex: collectionIndex)
                        .frame(width: dayColumnWidth)
                        .background(Color(.systemBackground))
                        .id("customlog\(collectionIndex)_day_\(index)")
                }
            }
            .frame(width: fixedWidth, alignment: .topLeading)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.15))
    }

    @ViewBuilder
    func weekLogRow(for logType: BuiltInLogType, dayColumnWidth: CGFloat, fixedWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    weekLogColumn(for: logType, date: date)
                        .frame(width: dayColumnWidth)
                        .background(Color(.systemBackground))
                        .id("\(logType.rawValue)_day_\(index)")
                }
            }
            .frame(width: fixedWidth, alignment: .topLeading)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.15))
    }

    @ViewBuilder
    func weekLogColumn(for logType: BuiltInLogType, date: Date) -> some View {
        switch logType {
        case .food: weekFoodLogColumn(date: date)
        case .sleep: weekSleepLogColumn(date: date)
        case .water: weekWaterLogColumn(date: date)
        case .weight: weekWeightLogColumn(date: date)
        case .workout: weekWorkoutLogColumn(date: date)
        }
    }

    @ViewBuilder
    func weekDayFixedLogCell(for logType: BuiltInLogType, date: Date, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch logType {
            case .food:
                let entries = getFoodLogsForDate(date)
                ForEach(entries, id: \.id) { entry in foodLogCard(entry: entry) }
            case .sleep:
                let entries = getSleepLogsForDate(date)
                ForEach(entries, id: \.id) { entry in sleepLogCard(entry: entry) }
            case .water:
                let entries = getWaterLogsForDate(date)
                ForEach(entries, id: \.id) { entry in waterLogCard(entry: entry) }
            case .weight:
                let entries = getWeightLogsForDate(date)
                ForEach(entries, id: \.id) { entry in weightLogCard(entry: entry) }
            case .workout:
                workoutStreakBadge(for: date)
                let entries = getWorkoutLogsForDate(date)
                ForEach(entries, id: \.id) { entry in workoutLogCard(entry: entry) }
            }
            Spacer(minLength: 0)
        }
        .padding(.all, 8)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 80)
    }

    @ViewBuilder
    func weekDayRowFlexLogCell(for logType: BuiltInLogType, date: Date, useFixedWidth: Bool) -> some View {
        if useFixedWidth {
            VStack(alignment: .leading, spacing: 4) {
                switch logType {
                case .food:
                    let entries = getFoodLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in foodLogCard(entry: entry) }
                case .sleep:
                    let entries = getSleepLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in sleepLogCard(entry: entry) }
                case .water:
                    let entries = getWaterLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in waterLogCard(entry: entry) }
                case .weight:
                    let entries = getWeightLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in weightLogCard(entry: entry) }
                case .workout:
                    workoutStreakBadge(for: date)
                    let entries = getWorkoutLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in workoutLogCard(entry: entry) }
                }
                Spacer(minLength: 0)
            }
            .padding(.all, 8)
            .frame(width: logColumnWidth(), alignment: .topLeading)
            .frame(minHeight: 80)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                switch logType {
                case .food:
                    let entries = getFoodLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in foodLogCard(entry: entry) }
                case .sleep:
                    let entries = getSleepLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in sleepLogCard(entry: entry) }
                case .water:
                    let entries = getWaterLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in waterLogCard(entry: entry) }
                case .weight:
                    let entries = getWeightLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in weightLogCard(entry: entry) }
                case .workout:
                    workoutStreakBadge(for: date)
                    let entries = getWorkoutLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in workoutLogCard(entry: entry) }
                }
                Spacer(minLength: 0)
            }
            .padding(.all, 8)
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        }
    }

    func weekWeightLogColumn(date: Date) -> some View {
        let weightLogsForDate = getWeightLogsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(weightLogsForDate, id: \.id) { entry in
                weekWeightLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    func weekWeightLogCard(entry: WeightLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Weight value
            Text("\(String(format: "%.1f", entry.weight)) \(entry.unit.displayName)")
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    func weekWorkoutLogColumn(date: Date) -> some View {
        let workoutLogsForDate = getWorkoutLogsForDate(date)

        return VStack(alignment: .leading, spacing: 4) {
            workoutStreakBadge(for: date)
            ForEach(workoutLogsForDate, id: \.id) { entry in
                weekWorkoutLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    func weekWorkoutLogCard(entry: WorkoutLogEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.displayIcon)
                .font(.body)
                .foregroundColor(appPrefs.colorForWorkoutType(entry.workoutType))
                .frame(width: 20)

            if !entry.name.isEmpty {
                Text(entry.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            } else {
                Text(entry.workoutType.displayName)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    func weekFoodLogColumn(date: Date) -> some View {
        let foodLogsForDate = getFoodLogsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(foodLogsForDate, id: \.id) { entry in
                weekFoodLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    func weekFoodLogCard(entry: FoodLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Bullet point
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Food name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    func weekCustomLogColumn(date: Date, collectionIndex: Int = 0) -> some View {
        let enabledItems = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }
        let completedCount = enabledItems.reduce(0) { count, item in
            count + (customLogManager.getCompletionStatus(for: item.id, date: date) ? 1 : 0)
        }
        
        return VStack(alignment: .leading, spacing: 2) {
            if !enabledItems.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.body)
                        .foregroundColor(.accentColor)
                    Text("\(completedCount)/\(enabledItems.count)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(6)
                
                // Show individual items
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(enabledItems) { item in
                        HStack(spacing: 8) {
                            Button(action: {
                                customLogManager.toggleEntry(for: item.id, date: date)
                            }) {
                                Image(systemName: customLogManager.getCompletionStatus(for: item.id, date: date) ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .foregroundColor(customLogManager.getCompletionStatus(for: item.id, date: date) ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Text(item.title)
                                .font(.body)
                                .strikethrough(customLogManager.getCompletionStatus(for: item.id, date: date))
                                .foregroundColor(customLogManager.getCompletionStatus(for: item.id, date: date) ? .secondary : .primary)
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    func weekEventCard(event: GoogleCalendarEvent) -> some View {
        let isAccount1 = event.ownerAccountKind == .account1
        let eventColor = isAccount1 ? appPrefs.account1Color : appPrefs.account2Color
        
        return Button(action: {
            selectedCalendarEvent = event
        }) {
            VStack(alignment: .leading, spacing: 2) {
                // Event time
                if let startTime = event.startTime {
                    Text(formatEventTimeShort(startTime))
                        .font(.caption2)
                        .foregroundColor(eventColor)
                        .fontWeight(.semibold)
                }
                
                // Event title
                Text(event.summary)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Event location (if available)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(eventColor.opacity(0.15))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(eventColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            let kind: GoogleAuthManager.AccountKind = isAccount1 ? .account1 : .account2
            let json: [String: String] = [
                "type": "event",
                "id": event.id,
                "accountKind": kind.rawValue,
                "calendarId": event.calendarId ?? "primary"
            ]
            let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
            let str = String(data: data, encoding: .utf8) ?? ""
            return NSItemProvider(object: str as NSString)
        }
    }

    func formatEventTimeShort(_ date: Date) -> String {
        DateFormatter.shortTime.string(from: date)
    }
    
    func getEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarViewModel.events(for: date)
    }
    
    func getWeightLogsForDate(_ date: Date) -> [WeightLogEntry] {
        logsViewModel.weightLogs(on: date)
    }
    
    func getWorkoutLogsForDate(_ date: Date) -> [WorkoutLogEntry] {
        logsViewModel.workoutLogs(on: date)
    }
    
    func getFoodLogsForDate(_ date: Date) -> [FoodLogEntry] {
        logsViewModel.foodLogs(on: date)
    }

    func getWaterLogsForDate(_ date: Date) -> [WaterLogEntry] {
        logsViewModel.waterLogs(on: date)
    }

    func weightLogCard(entry: WeightLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Time
            Text(formatLogTime(entry.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Weight value
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", entry.weight)) \(entry.unit.displayName)")
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    func formatLogTime(_ date: Date) -> String {
        DateFormatter.shortTime.string(from: date)
    }
    
    func workoutLogCard(entry: WorkoutLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Time
            Text(formatLogTime(entry.date))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Image(systemName: entry.displayIcon)
                .font(.body)
                .foregroundColor(appPrefs.colorForWorkoutType(entry.workoutType))
                .frame(width: 20)

            // Workout description
            VStack(alignment: .leading, spacing: 2) {
                if !entry.name.isEmpty {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                } else {
                    Text(entry.workoutType.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    func foodLogCard(entry: FoodLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Bullet point
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Food name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }

    func waterLogCard(entry: WaterLogEntry) -> some View {
        HStack(alignment: .center, spacing: 3) {
            // Display water drops
            ForEach(0..<entry.cupsConsumed, id: \.self) { _ in
                Image(systemName: "drop.fill")
                    .font(.body)
                    .foregroundColor(.blue)
            }

            // Display count
            Text("(\(entry.cupsConsumed))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    func weekWaterLogColumn(date: Date) -> some View {
        let waterLogsForDate = getWaterLogsForDate(date)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(waterLogsForDate, id: \.id) { entry in
                weekWaterLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func weekWaterLogCard(entry: WaterLogEntry) -> some View {
        HStack(alignment: .center, spacing: 3) {
            // Display water drops
            ForEach(0..<entry.cupsConsumed, id: \.self) { _ in
                Image(systemName: "drop.fill")
                    .font(.body)
                    .foregroundColor(.blue)
            }

            // Display count
            Text("(\(entry.cupsConsumed))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    func customLogSummary(items: [CustomLogItemData], date: Date) -> some View {
        let completedCount = items.reduce(0) { count, item in
            count + (customLogManager.getCompletionStatus(for: item.id, date: date) ? 1 : 0)
        }

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.body)
                    .foregroundColor(.accentColor)
                Text("\(completedCount)/\(items.count)")
                    .font(.body)
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button(action: {
                            customLogManager.toggleEntry(for: item.id, date: date)
                        }) {
                            Image(systemName: customLogManager.getCompletionStatus(for: item.id, date: date) ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundColor(customLogManager.getCompletionStatus(for: item.id, date: date) ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .font(.body)
                            .strikethrough(customLogManager.getCompletionStatus(for: item.id, date: date))
                            .foregroundColor(customLogManager.getCompletionStatus(for: item.id, date: date) ? .secondary : .primary)

                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
}
