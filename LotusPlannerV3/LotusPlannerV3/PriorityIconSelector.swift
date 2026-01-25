import SwiftUI

/// Icon-based priority selector component
/// Displays priority levels as tappable icons in a horizontal row
struct PriorityIconSelector: View {
    @Binding var selectedPriority: TaskPriorityData?

    var body: some View {
        HStack(spacing: 20) {
            // No Priority
            PriorityIconButton(
                icon: "circle.slash",
                label: "None",
                isSelected: selectedPriority == nil,
                color: .gray
            ) {
                selectedPriority = nil
            }

            // Low Priority (P4, P5)
            PriorityIconButton(
                icon: "minus",
                label: "Low",
                isSelected: selectedPriority?.value == "P4" || selectedPriority?.value == "P5",
                color: .blue
            ) {
                selectedPriority = TaskPriorityData(value: "P4")
            }

            // Medium Priority (P2, P3)
            PriorityIconButton(
                icon: "equal",
                label: "Medium",
                isSelected: selectedPriority?.value == "P2" || selectedPriority?.value == "P3",
                color: .orange
            ) {
                selectedPriority = TaskPriorityData(value: "P2")
            }

            // High Priority (P0, P1)
            PriorityIconButton(
                icon: "line.3.horizontal",
                label: "High",
                isSelected: selectedPriority?.value == "P0" || selectedPriority?.value == "P1",
                color: .red
            ) {
                selectedPriority = TaskPriorityData(value: "P0")
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
        VStack(spacing: 30) {
            Text("No Priority Selected")
            PriorityIconSelector(selectedPriority: .constant(nil))

            Text("Low Priority Selected")
            PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P4")))

            Text("Medium Priority Selected")
            PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P2")))

            Text("High Priority Selected")
            PriorityIconSelector(selectedPriority: .constant(TaskPriorityData(value: "P0")))
        }
        .padding()
    }
}
