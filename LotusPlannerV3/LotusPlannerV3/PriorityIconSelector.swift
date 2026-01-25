import SwiftUI

/// Icon-based priority selector component
/// Displays priority levels as tappable icons in a horizontal row
struct PriorityIconSelector: View {
    @Binding var selectedPriority: TaskPriorityData?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // No Priority
                PriorityIconButton(
                    icon: "circle.slash",
                    label: "None",
                    isSelected: selectedPriority == nil,
                    color: .gray
                ) {
                    selectedPriority = nil
                }

                // P0 - Highest Priority
                PriorityIconButton(
                    icon: "exclamationmark.3",
                    label: "P0",
                    isSelected: selectedPriority?.value == "P0",
                    color: .red
                ) {
                    selectedPriority = TaskPriorityData(value: "P0")
                }

                // P1
                PriorityIconButton(
                    icon: "exclamationmark.2",
                    label: "P1",
                    isSelected: selectedPriority?.value == "P1",
                    color: .red
                ) {
                    selectedPriority = TaskPriorityData(value: "P1")
                }

                // P2
                PriorityIconButton(
                    icon: "exclamationmark",
                    label: "P2",
                    isSelected: selectedPriority?.value == "P2",
                    color: .orange
                ) {
                    selectedPriority = TaskPriorityData(value: "P2")
                }
            }

            HStack(spacing: 16) {
                // P3
                PriorityIconButton(
                    icon: "minus",
                    label: "P3",
                    isSelected: selectedPriority?.value == "P3",
                    color: .yellow
                ) {
                    selectedPriority = TaskPriorityData(value: "P3")
                }

                // P4
                PriorityIconButton(
                    icon: "equal",
                    label: "P4",
                    isSelected: selectedPriority?.value == "P4",
                    color: .green
                ) {
                    selectedPriority = TaskPriorityData(value: "P4")
                }

                // P5 - Lowest Priority
                PriorityIconButton(
                    icon: "line.horizontal.3",
                    label: "P5",
                    isSelected: selectedPriority?.value == "P5",
                    color: .blue
                ) {
                    selectedPriority = TaskPriorityData(value: "P5")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// Individual priority icon button
private struct PriorityIconButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? color : .gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? color.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )

                Text(label)
                    .font(.caption2)
                    .foregroundColor(isSelected ? color : .gray)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct PriorityIconSelector_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text("No Priority Selected")
                PriorityIconSelector(selectedPriority: .constant(nil))

                Text("P0 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P0")))

                Text("P1 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P1")))

                Text("P2 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P2")))

                Text("P3 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P3")))

                Text("P4 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P4")))

                Text("P5 Selected")
                PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P5")))
            }
            .padding()
        }
    }
}
