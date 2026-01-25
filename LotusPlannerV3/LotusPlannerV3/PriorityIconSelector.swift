import SwiftUI

/// Icon-based priority selector component
/// Displays priority levels as tappable icons in a horizontal row
struct PriorityIconSelector: View {
    @Binding var selectedPriority: TaskPriorityData?

    var body: some View {
        HStack(spacing: 8) {
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
                icon: "0.square",
                label: "P0",
                isSelected: selectedPriority?.value == "P0",
                color: .red
            ) {
                selectedPriority = TaskPriorityData(value: "P0")
            }

            // P1
            PriorityIconButton(
                icon: "1.square",
                label: "P1",
                isSelected: selectedPriority?.value == "P1",
                color: .orange
            ) {
                selectedPriority = TaskPriorityData(value: "P1")
            }

            // P2
            PriorityIconButton(
                icon: "2.square",
                label: "P2",
                isSelected: selectedPriority?.value == "P2",
                color: .yellow
            ) {
                selectedPriority = TaskPriorityData(value: "P2")
            }

            // P3
            PriorityIconButton(
                icon: "3.square",
                label: "P3",
                isSelected: selectedPriority?.value == "P3",
                color: .green
            ) {
                selectedPriority = TaskPriorityData(value: "P3")
            }

            // P4 - Lowest Priority
            PriorityIconButton(
                icon: "4.square",
                label: "P4",
                isSelected: selectedPriority?.value == "P4",
                color: .blue
            ) {
                selectedPriority = TaskPriorityData(value: "P4")
            }
        }
        .padding(.vertical, 4)
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
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? color : .gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? color.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? color : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )

                Text(label)
                    .font(.system(size: 9))
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
            }
            .padding()
        }
    }
}
