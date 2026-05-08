import SwiftUI

// MARK: - Workout Type Selection View
struct WorkoutTypeSelectionView: View {
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var searchText = ""
    @State private var colorPickerType: WorkoutType?

    private var filteredTypes: [WorkoutType] {
        if searchText.isEmpty {
            return WorkoutType.allCases.map { $0 }
        }
        return WorkoutType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Button("Select All") {
                    appPrefs.selectedWorkoutTypes = Set(WorkoutType.allCases)
                }
                Button("Deselect All") {
                    appPrefs.selectedWorkoutTypes = []
                }
            }

            Section {
                ForEach(filteredTypes) { type in
                    HStack {
                        Button {
                            toggleType(type)
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(appPrefs.colorForWorkoutType(type))
                                    .frame(width: 24)
                                Text(type.displayName)
                                    .foregroundColor(.primary)
                            }
                        }

                        Spacer()

                        if appPrefs.selectedWorkoutTypes.contains(type) {
                            // Color circle
                            Button {
                                colorPickerType = type
                            } label: {
                                Circle()
                                    .fill(appPrefs.colorForWorkoutType(type))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Color(.systemGray3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            } footer: {
                Text("Selected types will appear in the workout type picker when adding or editing entries. Tap the color circle to change an icon's color.")
            }
        }
        .searchable(text: $searchText, prompt: "Search workout types")
        .navigationTitle("Workout Types")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $colorPickerType) { type in
            ColorPickerSheet(
                title: "\(type.displayName) Icon Color",
                selectedColor: Binding(
                    get: { appPrefs.colorForWorkoutType(type) },
                    set: { appPrefs.setColorForWorkoutType(type, color: $0) }
                ),
                onColorChange: { color in
                    appPrefs.setColorForWorkoutType(type, color: color)
                }
            )
        }
    }

    private func toggleType(_ type: WorkoutType) {
        if appPrefs.selectedWorkoutTypes.contains(type) {
            appPrefs.selectedWorkoutTypes.remove(type)
        } else {
            appPrefs.selectedWorkoutTypes.insert(type)
        }
    }
}
