import SwiftUI

// MARK: - Task Info for Goal Card
struct GoalCardTaskInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
}

// MARK: - Individual Goal Card
struct GoalCard: View {
    let goal: GoalData
    let category: GoalCategoryData
    let onTap: () -> Void
    let onEdit: () -> Void
    var taskInfos: [GoalCardTaskInfo] = []

    @ObservedObject private var goalsManager = GoalsManager.shared

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private var isOverdue: Bool {
        goal.daysRemaining <= 0 && !goal.isCompleted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Goal title with checkbox
            HStack(alignment: .top, spacing: 8) {
                Button {
                    goalsManager.toggleGoalCompletion(goal.id)
                } label: {
                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(goal.isCompleted ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())

                Text(goal.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .strikethrough(goal.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            // Category tag on its own line
            Text(category.title)
                .font(.caption2)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .fixedSize()

            // Tasks from pre-resolved taskInfos
            if !taskInfos.isEmpty {
                VStack(spacing: 6) {
                    ForEach(taskInfos) { info in
                        HStack(spacing: 8) {
                            Image(systemName: info.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(info.isCompleted ? .green : .secondary)
                                .font(.body)
                            Text(info.title)
                                .font(.subheadline)
                                .strikethrough(info.isCompleted)
                                .foregroundColor(info.isCompleted ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if let dueDate = info.dueDate {
                                let tag = dueDateTagInfo(dueDate, isCompleted: info.isCompleted)
                                Text(tag.text)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(tag.bgColor)
                                    .foregroundColor(tag.textColor)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray6).opacity(0.7))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private func dueDateTagInfo(_ date: Date, isCompleted: Bool) -> (text: String, textColor: Color, bgColor: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)

        if isCompleted {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        } else if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, .accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: date), .primary, Color(.systemGray5))
        }
    }
}

