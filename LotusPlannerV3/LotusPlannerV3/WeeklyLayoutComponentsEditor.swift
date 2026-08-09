import SwiftUI

/// Settings editor for which sections appear in Vertical / Horizontal weekly
/// layouts. Visibility only — render order stays fixed (events → tasks → logs).
struct WeeklyLayoutComponentsEditor: View {
    @ObservedObject private var appPrefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draftHidden: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose which components appear in both Vertical and Horizontal weekly layouts. Log order matches Log Preferences and cannot be changed here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Components") {
                    ForEach(WeeklyLayoutComponent.settingsOrder(logDisplayOrder: appPrefs.logDisplayOrder)) { component in
                        Toggle(isOn: binding(for: component)) {
                            HStack(spacing: 10) {
                                Image(systemName: component.systemImage)
                                    .foregroundColor(isVisible(component) ? .accentColor : .secondary)
                                    .frame(width: 22)
                                Text(displayName(for: component))
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Weekly Components")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appPrefs.replaceWeeklyLayoutHiddenComponents(draftHidden)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draftHidden = appPrefs.weeklyLayoutHiddenComponents
            }
        }
    }

    private func isVisible(_ component: WeeklyLayoutComponent) -> Bool {
        !draftHidden.contains(component.rawValue)
    }

    private func binding(for component: WeeklyLayoutComponent) -> Binding<Bool> {
        Binding(
            get: { isVisible(component) },
            set: { visible in
                if visible {
                    draftHidden.remove(component.rawValue)
                } else {
                    draftHidden.insert(component.rawValue)
                }
            }
        )
    }

    private func displayName(for component: WeeklyLayoutComponent) -> String {
        component.displayName(
            account1: appPrefs.account1Name,
            account2: appPrefs.account2Name,
            customLog: appPrefs.customLogSectionName(for: 0),
            customLog2: appPrefs.customLogSectionName(for: 1)
        )
    }
}
