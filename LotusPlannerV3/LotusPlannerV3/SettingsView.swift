import SwiftUI
import CoreData
import CloudKit
#if os(iOS)
import UIKit
#endif

#Preview {
    SettingsView()
}
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}






struct SettingsView: View {
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteSuccessAlert = false
    @State private var showingDeleteGoalsAlert = false
    @State private var showAccount1Account = true
    @State private var showAccount2Account = true
    @State private var showingAccount1ColorPicker = false
    @State private var showingAccount2ColorPicker = false
    @State private var pendingUnlink: GoogleAuthManager.AccountKind?
    /// Non-nil when a custom-day-view version is being edited; drives the
    /// configurator sheet. `UUID` identifies the slot in
    /// `CustomDayViewLibrary` being edited (pre-existing or brand-new).
    private struct ConfiguratorTarget: Identifiable { let id: UUID }
    @State private var configuratorTarget: ConfiguratorTarget?
    /// Used on Mac Catalyst to open the configurator in its own native window
    /// instead of the cramped .fullScreenCover sheet.
    @Environment(\.openWindow) private var openWindow
    @State private var pendingDeleteVersionId: UUID?
    /// Bumped after the configurator dismisses or the library changes so the
    /// versions list re-renders with the latest names / active selection.
    @State private var customConfigVersion = 0
    @State private var showingWeeklySummaryConfigurator = false
    @State private var showingWeeklyLayoutComponentsEditor = false

    // Check if device forces stacked layout (iPhone portrait)
    private var shouldUseStackedLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    /// Reading `customConfigVersion` creates a SwiftUI dependency so this
    /// recomputes after the configurator saves a new version.
    private var customDayViewLibrary: CustomDayViewLibrary {
        _ = customConfigVersion
        return CustomDayViewLibrary.load()
    }

    private var isCustomDayViewConfigured: Bool {
        !customDayViewLibrary.versions.isEmpty
    }

    /// The custom day view configurator currently only runs on iPad; layouts
    /// saved there sync to Mac via iCloud but Mac doesn't show the edit UI.
    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }

    // MARK: - Custom day view versions

    /// Sub-rows rendered under the Custom option in Daily View Preferences:
    /// each saved version (up to `CustomDayViewLibrary.maxVersions`) with
    /// radio-button selection of the live version, plus per-row Edit / Delete
    /// actions and an "Add Version" button when capacity remains.
    @ViewBuilder
    private var customDayViewVersionRows: some View {
        let library = customDayViewLibrary
        let canAddMore = library.versions.count < CustomDayViewLibrary.maxVersions

        ForEach(library.versions) { version in
            customDayViewVersionRow(version: version, activeId: library.resolvedActiveId)
        }

        if canAddMore {
            Button {
                addCustomDayViewVersion()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(.accentColor)
                    Text(library.versions.isEmpty ? "Add Version" : "Add Another Version")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text("\(library.versions.count) / \(CustomDayViewLibrary.maxVersions)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            Text("You've reached the limit of \(CustomDayViewLibrary.maxVersions) versions. Delete one to add another.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func customDayViewVersionRow(version: NamedCustomDayViewConfig, activeId: UUID?) -> some View {
        let isActive = version.id == activeId
        HStack(spacing: 10) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .font(.body)
                .contentShape(Rectangle())
                .onTapGesture {
                    setActiveCustomDayViewVersion(id: version.id)
                }

            // Inline editable name — reads from the library, writes back on
            // every change so renames persist without opening the configurator.
            TextField("Version name", text: Binding(
                get: {
                    customDayViewLibrary.versions.first(where: { $0.id == version.id })?.name ?? version.name
                },
                set: { newName in
                    renameCustomDayViewVersion(id: version.id, to: newName)
                }
            ))
            .textFieldStyle(.plain)
            .font(.footnote)
            .fontWeight(isActive ? .semibold : .regular)
            .lineLimit(1)
            .submitLabel(.done)

            Spacer(minLength: 4)

            Button {
                #if targetEnvironment(macCatalyst)
                openWindow(id: "configurator", value: version.id)
                #else
                configuratorTarget = ConfiguratorTarget(id: version.id)
                #endif
            } label: {
                Text("Edit Layout")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                pendingDeleteVersionId = version.id
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 28)
    }

    /// Creates a blank new version with a default name and immediately opens
    /// the configurator to edit it. The version isn't persisted until the
    /// user taps Save in the configurator.
    private func addCustomDayViewVersion() {
        let library = customDayViewLibrary
        guard library.versions.count < CustomDayViewLibrary.maxVersions else { return }
        let newId = UUID()
        #if targetEnvironment(macCatalyst)
        openWindow(id: "configurator", value: newId)
        #else
        configuratorTarget = ConfiguratorTarget(id: newId)
        #endif
    }

    private func setActiveCustomDayViewVersion(id: UUID) {
        let library = CustomDayViewLibrary.load()
        guard library.versions.contains(where: { $0.id == id }) else { return }
        // Per-device selection. Does NOT touch the synced library, so
        // selecting a different version on this device leaves other devices'
        // selections untouched.
        guard CustomDayViewLibrary.localActiveId != id else { return }
        CustomDayViewLibrary.localActiveId = id
    }

    /// Persists an inline name change for a specific version. Called on every
    /// keystroke from the TextField in the settings row.
    private func renameCustomDayViewVersion(id: UUID, to newName: String) {
        var library = CustomDayViewLibrary.load()
        guard let idx = library.versions.firstIndex(where: { $0.id == id }) else { return }
        guard library.versions[idx].name != newName else { return }
        library.versions[idx].name = newName
        CustomDayViewLibrary.save(library)
    }

    private func deleteCustomDayViewVersion(id: UUID) {
        var library = CustomDayViewLibrary.load()
        library.versions.removeAll { $0.id == id }
        if library.activeId == id {
            // Fall back to the first remaining version (if any) so the Custom
            // day view keeps rendering something sensible on devices that
            // had no per-device override.
            library.activeId = library.versions.first?.id
        }
        if CustomDayViewLibrary.localActiveId == id {
            // This device pointed at the deleted version; clear so it falls
            // back to the synced default (or the first remaining version).
            CustomDayViewLibrary.localActiveId = nil
        }
        CustomDayViewLibrary.save(library)
        if library.versions.isEmpty && appPrefs.dayViewLayout == .custom {
            appPrefs.updateDayViewLayout(.newClassic)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Linked Accounts") {
                    accountRow(
                        kind: appPrefs.account1Name,
                        kindEnum: .account1,
                        isVisible: $showAccount1Account,
                        accountColor: $appPrefs.account1Color,
                        showingColorPicker: $showingAccount1ColorPicker
                    )
                    accountRow(
                        kind: appPrefs.account2Name,
                        kindEnum: .account2,
                        isVisible: $showAccount2Account,
                        accountColor: $appPrefs.account2Color,
                        showingColorPicker: $showingAccount2ColorPicker
                    )
                }

                // Task Management section removed (Hide Completed Tasks now controlled via eye icon)

                if !AppPreferences.isRunningOniPhone {
                    Section("Events View Preferences") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: !appPrefs.showEventsAsListInDay ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(!appPrefs.showEventsAsListInDay ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Events in a 24-hour timeline")
                                        .font(.body)
                                        .fontWeight(!appPrefs.showEventsAsListInDay ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateShowEventsAsListInDay(false)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: appPrefs.showEventsAsListInDay ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(appPrefs.showEventsAsListInDay ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Events in a list")
                                        .font(.body)
                                        .fontWeight(appPrefs.showEventsAsListInDay ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateShowEventsAsListInDay(true)
                        }
                    }
                }

                Section("Daily View Preferences") {
                    // Day View Layout Options with Radio Buttons
                    ForEach(appPrefs.availableDayViewLayouts) { option in
                        let canSelect = option != .custom || isCustomDayViewConfigured
                        Group {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: appPrefs.dayViewLayout == option ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(
                                                canSelect
                                                ? (appPrefs.dayViewLayout == option ? .accentColor : .secondary)
                                                : .secondary.opacity(0.4)
                                            )
                                            .font(.title2)

                                        Text(option.displayName)
                                            .font(.body)
                                            .fontWeight(appPrefs.dayViewLayout == option ? .semibold : .regular)
                                            .foregroundColor(canSelect ? .primary : .secondary)

                                        if option.isBeta {
                                            Text("Beta")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().fill(Color.orange)
                                                )
                                        }

                                    }

                                    Text(
                                        option == .custom && !canSelect
                                        ? "Save at least one custom layout before selecting this view."
                                        : option.description
                                    )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 28)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if canSelect {
                                    appPrefs.updateDayViewLayout(option)
                                }
                            }

                            // Render the saved-versions manager as sub-rows
                            // directly under the Custom option, so users can
                            // add / rename / pick active versions without
                            // leaving the Daily View Preferences section.
                            if option == .custom {
                                customDayViewVersionRows
                            }
                        }
                    }
                }

                // Weekly View Preference
                Section("Weekly View Preferences") {
                    HStack(spacing: 10) {
                        HStack {
                            Image(systemName: !appPrefs.useRowBasedWeeklyView ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(!appPrefs.useRowBasedWeeklyView ? .accentColor : .secondary)
                                .font(.title2)

                            Text("Vertical Layout (week in 7 columns)")
                                .font(.body)
                                .fontWeight(!appPrefs.useRowBasedWeeklyView ? .semibold : .regular)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateUseRowBasedWeeklyView(false)
                        }

                        Button {
                            showingWeeklyLayoutComponentsEditor = true
                        } label: {
                            Text("Edit")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        HStack {
                            Image(systemName: appPrefs.useRowBasedWeeklyView ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(appPrefs.useRowBasedWeeklyView ? .accentColor : .secondary)
                                .font(.title2)

                            Text("Horizontal Layout (week in 7 rows)")
                                .font(.body)
                                .fontWeight(appPrefs.useRowBasedWeeklyView ? .semibold : .regular)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateUseRowBasedWeeklyView(true)
                        }

                        Button {
                            showingWeeklyLayoutComponentsEditor = true
                        } label: {
                            Text("Edit")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Toggle(isOn: Binding(
                        get: { appPrefs.showWeeklySummarySection },
                        set: { appPrefs.updateShowWeeklySummarySection($0) }
                    )) {
                        HStack {
                            Image(systemName: "rectangle.leadinghalf.inset.filled")
                                .foregroundColor(appPrefs.showWeeklySummarySection ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Weekly Summary")
                                    .font(.body)
                                Text(appPrefs.useRowBasedWeeklyView ? "Adds a summary row before Monday." : "Adds a summary column before Monday.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if appPrefs.showWeeklySummarySection {
                        Button {
                            #if targetEnvironment(macCatalyst)
                            openWindow(id: "weekly-summary-configurator")
                            #else
                            showingWeeklySummaryConfigurator = true
                            #endif
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Customize Weekly Summary")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 28)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Tasks View Preference
                Section("Tasks View Preferences") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: !appPrefs.tasksLayoutHorizontal ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(!appPrefs.tasksLayoutHorizontal ? .accentColor : .secondary)
                                    .font(.title2)
                                
                                Text("Vertical stacks")
                                    .font(.body)
                                    .fontWeight(!appPrefs.tasksLayoutHorizontal ? .semibold : .regular)
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appPrefs.updateTasksLayoutHorizontal(false)
                    }
                    
                    if !AppPreferences.isRunningOniPhone {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: appPrefs.tasksLayoutHorizontal ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(appPrefs.tasksLayoutHorizontal ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Horizontal stacks")
                                        .font(.body)
                                        .fontWeight(appPrefs.tasksLayoutHorizontal ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateTasksLayoutHorizontal(true)
                        }
                    }
                }

                Section("Log Preferences") {
                    ForEach(appPrefs.logDisplayOrder) { entry in
                        switch entry {
                        case .builtIn(let logType):
                            logToggleRow(for: logType)
                        case .custom:
                            customLogToggleRow(collection: 0)
                        case .custom2:
                            customLogToggleRow(collection: 1)
                        }
                    }
                    .onMove { source, destination in
                        appPrefs.moveLog(from: source, to: destination)
                    }
                }

                Section("Health Bar Preferences") {
                    Text("Contents of the Health Bar component in the Custom Day View, in the order they appear. Drag to reorder and toggle to show or hide.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(appPrefs.healthBarOrder) { item in
                        healthBarItemRow(item)
                    }
                    .onMove { source, destination in
                        appPrefs.moveHealthBarItem(from: source, to: destination)
                    }
                }

                Section("Apple Health Kit Preferences") {
                    appleHealthKitSection()
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { !appPrefs.hideGoals },
                        set: { appPrefs.updateHideGoals(!$0) }
                    )) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(appPrefs.hideGoals ? .secondary : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Goals")
                                    .font(.body)
                                Text("Enable goal management features")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !appPrefs.hideGoals {
                        GoalCategoriesInlineView()
                            .padding(.leading, 20)
                            .padding(.top, 8)
                    }
                } header: {
                    Text("Goal Preferences")
                }

                // Book View section - temporarily hidden
//                Section {
//                    Toggle(isOn: Binding(
//                        get: { !appPrefs.hideBookView },
//                        set: { appPrefs.updateHideBookView(!$0) }
//                    )) {
//                        HStack {
//                            Image(systemName: "book.pages")
//                                .foregroundColor(appPrefs.hideBookView ? .secondary : .accentColor)
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Enable Book View")
//                                    .font(.body)
//                                Text("Show Book View option in navigation menu")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                        }
//                    }
//                } header: {
//                    HStack(spacing: 8) {
//                        Text("Book View")
//                        Text("Beta")
//                            .font(.caption2)
//                            .fontWeight(.semibold)
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 6)
//                            .padding(.vertical, 2)
//                            .background(Color.orange)
//                            .clipShape(RoundedRectangle(cornerRadius: 4))
//                    }
//                } footer: {
//                    Text("Book View lets you swipe through your planner like a book. This feature is still in beta.")
//                }

                Section("App Preferences") {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark Mode")
                                .font(.body)
                            Text("Use dark appearance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { appPrefs.isDarkMode },
                            set: { appPrefs.updateDarkMode($0) }
                        ))
                    }
                    
                }
                
                
                // Components Visibility section removed: Logs and Journal are always visible
                
                
                

                Section("Danger Zone") {
                    Button(role: .destructive) {
                        showingDeleteGoalsAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(.red)
                            Text("Delete All Goals Data")
                        }
                    }
                    .alert("Delete All Goals?", isPresented: $showingDeleteGoalsAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete All Goals", role: .destructive) {
                            GoalsManager.shared.deleteAllData()
                        }
                    } message: {
                        Text("This will permanently delete all goals and goal categories. This action cannot be undone.")
                    }

                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete All Data")
                        }
                    }
                    .alert("Delete All Data?", isPresented: $showingDeleteAllAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) {
                            handleDeleteAllData()
                        }
                    } message: {
                        Text("This action will unlink all your linked Google accounts but will not delete the events or tasks data from your Google accounts. \n\nLogs data, however, will be deleted from your iCloud and cannot be undone.")
                    }
                    .alert("Data Deleted Successfully", isPresented: $showingDeleteSuccessAlert) {
                        Button("OK") {}
                    } message: {
                        Text("All app data has been deleted successfully. The current view has been refreshed to reflect the changes.")
                    }
                }
                

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Toggle the source binding directly. On Mac Catalyst,
                        // `@Environment(\.dismiss)` becomes unreliable once the
                        // sheet's content has mutated state — dismiss() silently
                        // no-ops, leaving the user unable to close Settings until
                        // backgrounding the app. Setting `showingSettings = false`
                        // sidesteps that path. Also calling `dismiss()` as a
                        // belt-and-suspenders for non-Catalyst contexts.
                        navigationManager.dismissActiveSheet()
                        dismiss()
                    }
                }
            }
            .alert(
                "Unlink Account?",
                isPresented: Binding(
                    get: { pendingUnlink != nil },
                    set: { if !$0 { pendingUnlink = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingUnlink = nil }
                Button("Unlink", role: .destructive) {
                    if let kind = pendingUnlink {
                        handleTap(kind)
                        pendingUnlink = nil
                    }
                }
            } message: {
                Text("You will stop syncing data for this account. You can re-link anytime in Settings.")
            }
            #if !targetEnvironment(macCatalyst)
            .sheet(item: $configuratorTarget, onDismiss: {
                customConfigVersion &+= 1
            }) { target in
                DayViewCustomConfigurator(versionId: target.id)
                    .presentationDetents([.fraction(0.72), .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingWeeklySummaryConfigurator) {
                WeeklySummaryConfigurator()
            }
            #endif
            .sheet(isPresented: $showingWeeklyLayoutComponentsEditor) {
                WeeklyLayoutComponentsEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: CustomDayViewLibrary.didChangeNotification)) { _ in
                customConfigVersion &+= 1
            }
            .confirmationDialog(
                "Delete this custom day view?",
                isPresented: Binding(
                    get: { pendingDeleteVersionId != nil },
                    set: { if !$0 { pendingDeleteVersionId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteVersionId {
                        deleteCustomDayViewVersion(id: id)
                    }
                    pendingDeleteVersionId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteVersionId = nil
                }
            } message: {
                Text("The layout for this version will be removed. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func accountRow(
        kind: String,
        kindEnum: GoogleAuthManager.AccountKind,
        isVisible: Binding<Bool>,
        accountColor: Binding<Color>,
        showingColorPicker: Binding<Bool>
    ) -> some View {
        let isLinked = auth.linkedStates[kindEnum] ?? false
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)

                Button {
                    showingColorPicker.wrappedValue = true
                } label: {
                    Circle()
                        .fill(accountColor.wrappedValue)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: showingColorPicker) {
                    ColorPickerSheet(
                        title: "\(kind) Account Color",
                        selectedColor: accountColor,
                        onColorChange: { color in
                            switch kindEnum {
                            case .account1:
                                appPrefs.updateAccount1Color(color)
                            case .account2:
                                appPrefs.updateAccount2Color(color)
                            }
                        }
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Account name", text: kindEnum == .account1 ? $appPrefs.account1Name : $appPrefs.account2Name)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 200)
                    Text(isLinked ? (auth.getEmail(for: kindEnum).isEmpty ? "Linked" : auth.getEmail(for: kindEnum)) : "Not Linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isLinked ? "Unlink" : "Link") {
                    if isLinked {
                        pendingUnlink = kindEnum
                    } else {
                        handleTap(kindEnum)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func handleTap(_ kind: GoogleAuthManager.AccountKind) {
        if auth.isLinked(kind: kind) {
            auth.unlink(kind: kind)
        } else {
            Task {
                do {
                    try await auth.link(kind: kind, presenting: nil)
                } catch GoogleAuthManager.AuthError.missingClientID {
                } catch GoogleAuthManager.AuthError.noRefreshToken {
                } catch GoogleAuthManager.AuthError.tokenRefreshFailed {
                } catch {
                }
            }
        }
    }
    
    private func handleDeleteAllData() {
        // Unlink all Google accounts
        GoogleAuthManager.shared.clearAllAuthState()
        
        // Clear calendar caches
        CalendarViewModel.shared.clearAllData()
        
        // Delete all Logs data (Core Data + CloudKit)
        CoreDataManager.shared.deleteAllLogs()
        LogsViewModel.shared.reloadData()
        LogsViewModel.shared.loadLogsForCurrentDate()
        
        // Delete all Custom Logs data (Core Data + CloudKit)
        CustomLogManager.shared.deleteAllData()
        
        // Delete all Goals data (Core Data + CloudKit)
        GoalsManager.shared.deleteAllData()
        
        // Delete all journal data (drawings, photos, background PDFs)
        JournalManager.shared.deleteAllJournalData()
        
        // Force comprehensive UI refresh
        Task {
            await refreshAllViewsAfterDelete()
            
            // Show success confirmation
            DispatchQueue.main.async {
                showingDeleteSuccessAlert = true
            }
        }
    }
    
    /// Single-collection variant of the custom-log row used in the
    /// reorderable Log Preferences list. Each `.custom` / `.custom2`
    /// entry in `logDisplayOrder` renders one of these so the rows can
    /// be dragged independently.
    @ViewBuilder
    private func customLogToggleRow(collection: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { appPrefs.showCustomLogs(for: collection) },
                set: { appPrefs.updateShowCustomLogs($0, for: collection) }
            )) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(appPrefs.showCustomLogs(for: collection) ? .accentColor : .secondary)
                    TextField(
                        collection == 0 ? "Custom Logs" : "Custom Logs \(collection + 1)",
                        text: Binding(
                            get: { appPrefs.customLogSectionName(for: collection) },
                            set: { appPrefs.updateCustomLogSectionName($0, for: collection) }
                        )
                    )
                    .font(.body)
                    .textFieldStyle(.plain)
                }
            }

            if appPrefs.showCustomLogs(for: collection) {
                CustomLogItemsInlineView(collectionIndex: collection)
                    .padding(.leading, 20)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var customLogToggleRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            // One toggle + inline editor per collection. Each toggle
            // independently controls visibility of its collection in
            // day views; the user can turn one, the other, or both on.
            ForEach(0..<CustomLogManager.maxCollections, id: \.self) { collection in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { appPrefs.showCustomLogs(for: collection) },
                        set: { appPrefs.updateShowCustomLogs($0, for: collection) }
                    )) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(appPrefs.showCustomLogs(for: collection) ? .accentColor : .secondary)
                            TextField(
                                collection == 0 ? "Custom Logs" : "Custom Logs \(collection + 1)",
                                text: Binding(
                                    get: { appPrefs.customLogSectionName(for: collection) },
                                    set: { appPrefs.updateCustomLogSectionName($0, for: collection) }
                                )
                            )
                            .font(.body)
                            .textFieldStyle(.plain)
                        }
                    }

                    if appPrefs.showCustomLogs(for: collection) {
                        CustomLogItemsInlineView(collectionIndex: collection)
                            .padding(.leading, 20)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func healthBarItemRow(_ item: HealthBarItem) -> some View {
        let visible = appPrefs.isHealthBarItemVisible(item)
        Toggle(isOn: Binding(
            get: { visible },
            set: { appPrefs.setHealthBarItem(item, visible: $0) }
        )) {
            HStack {
                Image(systemName: item.systemImage)
                    .foregroundColor(visible ? .accentColor : .secondary)
                    .frame(width: 22)
                Text(item.displayName)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private func logToggleRow(for logType: BuiltInLogType) -> some View {
        switch logType {
        case .food:
            Toggle(isOn: Binding(
                get: { appPrefs.showFoodLogs },
                set: { appPrefs.showFoodLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundColor(appPrefs.showFoodLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Food Logs")
                            .font(.body)
                        Text("Show food tracking in day views")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .sleep:
            Toggle(isOn: Binding(
                get: { appPrefs.showSleepLogs },
                set: { appPrefs.showSleepLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "bed.double.fill")
                        .foregroundColor(appPrefs.showSleepLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Logs")
                            .font(.body)
                        Text("Track wake up time and bed time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .water:
            Toggle(isOn: Binding(
                get: { appPrefs.showWaterLogs },
                set: { appPrefs.showWaterLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(appPrefs.showWaterLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Water Logs")
                            .font(.body)
                        Text("Track daily water intake in cups")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .weight:
            Toggle(isOn: Binding(
                get: { appPrefs.showWeightLogs },
                set: { appPrefs.showWeightLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "scalemass")
                        .foregroundColor(appPrefs.showWeightLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight Logs")
                            .font(.body)
                        Text("Show weight tracking in day views")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .workout:
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { appPrefs.showWorkoutLogs },
                    set: { appPrefs.showWorkoutLogs = $0 }
                )) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(appPrefs.showWorkoutLogs ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout Logs")
                                .font(.body)
                            Text("Show workout tracking in day views")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if appPrefs.showWorkoutLogs {
                    Divider().padding(.vertical, 8)

                    NavigationLink {
                        WorkoutTypeSelectionView()
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout Types")
                                    .font(.body)
                                Text("\(appPrefs.selectedWorkoutTypes.count) of \(WorkoutType.allCases.count) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 20)

                    Divider().padding(.vertical, 8)

                    Toggle(isOn: $appPrefs.showWorkoutStreak) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(appPrefs.showWorkoutStreak ? .orange : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout Streak")
                                    .font(.body)
                                Text("Show rolling 7-day workout count in weekly view")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 20)
                    // Activity Rings + other Apple Health toggles now live in
                    // their own "Apple Health Kit Preferences" section.
                }
            }
        }
    }

    @ViewBuilder
    private func appleHealthKitSection() -> some View {
        if HealthKitManager.shared.isHealthKitAvailable {
            Toggle(isOn: $appPrefs.showActivityRings) {
                healthKitRowLabel(
                    icon: "circle.circle",
                    iconColor: appPrefs.showActivityRings ? .red : .secondary,
                    title: "Activity Rings",
                    subtitle: "Move, Exercise, and Stand rings"
                )
            }

            Toggle(isOn: $appPrefs.showHKSteps) {
                healthKitRowLabel(
                    icon: "shoeprints.fill",
                    iconColor: appPrefs.showHKSteps ? .green : .secondary,
                    title: "Steps",
                    subtitle: "Daily step count from Apple Health"
                )
            }

            Toggle(isOn: $appPrefs.showHKActiveEnergy) {
                healthKitRowLabel(
                    icon: "figure.arms.open",
                    iconColor: appPrefs.showHKActiveEnergy ? .orange : .secondary,
                    title: "Active Energy",
                    subtitle: "Calories burned moving today"
                )
            }

            Toggle(isOn: $appPrefs.showHKRestingEnergy) {
                healthKitRowLabel(
                    icon: "gauge.medium",
                    iconColor: appPrefs.showHKRestingEnergy ? .indigo : .secondary,
                    title: "Resting Energy",
                    subtitle: "Basal calories burned today"
                )
            }

            Picker(selection: $appPrefs.weightSource) {
                ForEach(AppPreferences.WeightSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                healthKitRowLabel(
                    icon: "scalemass.fill",
                    iconColor: .teal,
                    title: "Weight Source",
                    subtitle: "Where the Weight chip's value comes from"
                )
            }

            Picker(selection: $appPrefs.workoutSource) {
                ForEach(AppPreferences.WorkoutSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                healthKitRowLabel(
                    icon: "figure.run",
                    iconColor: .pink,
                    title: "Workout Source",
                    subtitle: "Where the Workout chips come from"
                )
            }
        } else {
            healthKitRowLabel(
                icon: "heart.slash",
                iconColor: .secondary,
                title: "Apple Health unavailable",
                subtitle: "This device does not support Apple Health."
            )
        }
    }

    @ViewBuilder
    private func healthKitRowLabel(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }


    private func refreshAllViewsAfterDelete() async {
        let currentDate = NavigationManager.shared.currentDate
        
        // Reload calendar events based on current interval
        switch NavigationManager.shared.currentInterval {
        case .day:
            await CalendarViewModel.shared.loadCalendarData(for: currentDate)
        case .week:
            await CalendarViewModel.shared.loadCalendarDataForWeek(containing: currentDate)
        case .month:
            await CalendarViewModel.shared.loadCalendarDataForMonth(containing: currentDate)
        case .year:
            await CalendarViewModel.shared.loadCalendarDataForMonth(containing: currentDate)
        }
        
        // Reload tasks with forced cache clear
        await TasksViewModel.shared.loadTasks(forceClear: true)

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        GoalsManager.shared.refreshData()

        // Reload custom log data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        CustomLogManager.shared.refreshData()

        // Reload logs data
        LogsViewModel.shared.reloadData()
        LogsViewModel.shared.loadLogsForCurrentDate()
        
        // Post comprehensive refresh notifications
        NotificationCenter.default.post(name: .refreshJournalContent, object: nil)
        NotificationCenter.default.post(name: .refreshAllData, object: nil)
        NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
        
        // Force NavigationManager refresh to update all UI components
        let current = NavigationManager.shared.currentDate
        NavigationManager.shared.updateInterval(NavigationManager.shared.currentInterval, date: current)
    }
    
    private func testGoogleSignInConfig() {
        
        // Check Info.plist configuration
        _ = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        
        _ = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        
        // Check URL schemes
        _ = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        
        // Check current authentication states
        _ = auth.isLinked(kind: .account1)
        _ = auth.getEmail(for: .account1)
        _ = auth.isLinked(kind: .account2)
        _ = auth.getEmail(for: .account2)
        
        // Check UserDefaults for tokens
        let _ = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("google") }
        
        // Completed test
    }
    
    private func clearAllAuthTokens() {
        
        // Get all Google-related UserDefaults keys
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let googleKeys = allKeys.filter { $0.contains("google") }
        
        // Remove all Google-related keys
        for key in googleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Force update authentication states
        auth.unlink(kind: .account1)
        auth.unlink(kind: .account2)
        
        // Cleared tokens
    }
}
