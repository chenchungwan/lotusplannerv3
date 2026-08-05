import SwiftUI
import CoreData
import CloudKit

/// Standalone Diagnostics sheet, presented from the hamburger menu.
/// Mirrors the inline Diagnostics section in Settings but adds the app's
/// version and build at the top so support reports can be self-contained.
///
/// The helper functions duplicate Settings' equivalents intentionally —
/// they all operate on global singletons (`PersistenceController.shared`,
/// `iCloudManager.shared`, `CKContainer`) and don't depend on Settings'
/// state, so duplication is safe. A later pass can lift them into a shared
/// helper module if either copy needs to evolve.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iCloudManagerInstance = iCloudManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared

    // iCloud Sync section state (moved from SettingsView).
    @State private var cachedSyncStatus: iCloudManager.SyncStatus = .unknown
    @State private var cachedCloudAvailability = true
    @State private var syncButtonDisabled = false
    @State private var showingSyncProgress = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud Sync") {
                    iCloudSyncBlock
                }

                Section("Quality") {
                    qualityBlock
                }

                Section {
                    HStack {
                        Text("Version:")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build:")
                        Spacer()
                        Text(buildNumber)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    statusBlock
                }

                Section {
                    verboseLoggingBlock
                }

                Section {
                    cloudKitDiagnosticsBlock
                }

                Section {
                    syncDiagnosticsBlock
                }

                Section {
                    containerInfoBlock
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - UI blocks

    private var qualityBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            qualityRow("Sync Health", iCloudManagerInstance.syncStatus.description)
            qualityRow("Last iCloud Save", iCloudManagerInstance.lastSyncDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            qualityRow("Personal Account", linkedAccountSummary(.personal))
            qualityRow("Professional Account", linkedAccountSummary(.professional))
            qualityRow("Calendar Personal", calendarVM.qualitySummary(for: .personal))
            qualityRow("Calendar Professional", calendarVM.qualitySummary(for: .professional))
            qualityRow("Tasks Personal", tasksVM.qualitySummary(for: .personal))
            qualityRow("Tasks Professional", tasksVM.qualitySummary(for: .professional))
            qualityRow("Calendar Cache", calendarVM.newestCacheAgeDescription())
            qualityRow("Task Cache", tasksVM.newestCacheAgeDescription())
            qualityRow("App Version", "\(appVersion) (\(buildNumber))")

            HStack {
                Button {
                    Task {
                        await calendarVM.retryCurrentLoad()
                        await tasksVM.loadTasks(policy: .forceRefresh)
                    }
                } label: {
                    Label("Retry Google Fetch", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func qualityRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func linkedAccountSummary(_ kind: GoogleAuthManager.AccountKind) -> String {
        guard auth.isLinked(kind: kind) else { return "Not linked" }
        let email = auth.getEmail(for: kind)
        return email.isEmpty ? "Linked" : email
    }

    private var iCloudSyncBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: iCloudManagerInstance.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                    .foregroundColor(iCloudManagerInstance.iCloudAvailable ? .blue : .red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Status")
                        .font(.body)
                    Text(iCloudManagerInstance.syncStatus.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .onAppear {
                cachedSyncStatus = iCloudManagerInstance.syncStatus
                cachedCloudAvailability = iCloudManagerInstance.iCloudAvailable
                updateSyncButtonState(status: cachedSyncStatus, available: cachedCloudAvailability, logChange: false)
            }

            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
                .opacity(showingSyncProgress ? 1 : 0)
                .frame(height: 4)
                .animation(.easeInOut(duration: 0.25), value: showingSyncProgress)

            Button(action: {
                devLog("🔵 SYNC BUTTON TAPPED!")
                Task { await performManualSync() }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(syncButtonDisabled)

            if let lastSync = iCloudManagerInstance.lastSyncDate {
                Text("Last sync: \(lastSync, formatter: DateFormatter.shortDateTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onReceive(iCloudManagerInstance.$syncStatus) { status in
            cachedSyncStatus = status
            updateSyncButtonState(status: status, available: cachedCloudAvailability, logChange: true)
        }
        .onReceive(iCloudManagerInstance.$iCloudAvailable) { available in
            cachedCloudAvailability = available
            updateSyncButtonState(status: cachedSyncStatus, available: available, logChange: true)
        }
    }

    private func updateSyncButtonState(status: iCloudManager.SyncStatus, available: Bool, logChange: Bool) {
        let isSyncing = status == .syncing
        let disabled = isSyncing || !available
        if logChange && (isSyncing != showingSyncProgress || disabled != syncButtonDisabled) {
            devLog("🔍 Sync state update - syncing: \(isSyncing), available: \(available), disabled: \(disabled)")
        }
        showingSyncProgress = isSyncing
        syncButtonDisabled = disabled
    }

    private func performManualSync() async {
        iCloudManagerInstance.forceCompleteSync()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await MainActor.run {
            let beforeCount = TaskTimeWindowManager.shared.timeWindows.count
            TaskTimeWindowManager.shared.loadTimeWindows()
            CustomLogManager.shared.refreshData()
            LogsViewModel.shared.reloadData()
            let afterCount = TaskTimeWindowManager.shared.timeWindows.count
            if afterCount != beforeCount {
                devLog("✅ DiagnosticsView: Manual sync completed - task time windows changed (\(beforeCount) → \(afterCount))")
            }
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }
        iCloudManagerInstance.lastSyncDate = Date()
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Status")
                    .font(.headline)
            }

            Divider()

            HStack {
                Text("iCloud Available:")
                Spacer()
                Text(iCloudManagerInstance.iCloudAvailable ? "✅ Yes" : "❌ No")
                    .foregroundColor(iCloudManagerInstance.iCloudAvailable ? .green : .red)
                    .bold()
            }

            HStack {
                Text("Status:")
                Spacer()
                Text(iCloudManagerInstance.syncStatus.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Last Sync:")
                Spacer()
                if let lastSync = iCloudManagerInstance.lastSyncDate {
                    Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                } else {
                    Text("Never")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Environment:")
                Spacer()
                #if DEBUG
                Text("Development")
                    .foregroundColor(.orange)
                    .bold()
                #else
                Text("Production")
                    .foregroundColor(.green)
                    .bold()
                #endif
            }
        }
        .padding(.vertical, 4)
    }

    private var verboseLoggingBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { appPrefs.verboseLoggingEnabled },
                set: { appPrefs.updateVerboseLogging($0) }
            )) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(appPrefs.verboseLoggingEnabled ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verbose Console Logging")
                            .font(.body)
                        Text("Adds detailed console output for troubleshooting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Text("When disabled, only warnings and errors are logged. Enable to see detailed CloudKit sync logs in Console.app.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
    }

    private var cloudKitDiagnosticsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                devLog("🔍 Running CloudKit diagnostics...")
                iCloudManagerInstance.diagnoseICloudSetup()
                Task { await iCloudManagerInstance.diagnoseCloudKitData() }
            } label: {
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run CloudKit Diagnostics")
                            .font(.body)
                        Text("Check CloudKit setup and data (view output in Console.app)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Text("Connect device via USB → Open Console.app on Mac → Filter by 'LotusPlannerV3' → Tap this button → Look for 🔍 DIAGNOSTICS logs")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
    }

    private var syncDiagnosticsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                checkAllDataUserIds()
            } label: {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check ALL Data userId Values")
                            .font(.body)
                        Text("Shows userId for Goals, Logs, Task Windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                fixAllDataUserIds()
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fix ALL Data userId Values")
                            .font(.body)
                        Text("Sets userId='icloud-user' on ALL entities")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                Task { await checkCloudKitRawData() }
            } label: {
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Query CloudKit Directly")
                            .font(.body)
                        Text("Check what's actually in CloudKit Production")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                forceExportToCloudKit()
            } label: {
                HStack {
                    Image(systemName: "arrow.up.to.line.compact")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Force Export to CloudKit")
                            .font(.body)
                        Text("Touch all entities to trigger CloudKit upload")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("DEV→PROD sync issue: Fix ALL Data → Force Export → Sync Now → Wait 2 min → Query CloudKit → Check if counts increased")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
    }

    private var containerInfoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("CloudKit Container")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("iCloud.com.chenchungwan.LotusPlannerV3")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
        }
    }

    // MARK: - Helpers (mirror SettingsView's diagnostic helpers)

    private func checkAllDataUserIds() {
        let context = PersistenceController.shared.container.viewContext

        devLog("🔍 ========== COMPREHENSIVE DATA CHECK ==========")
        devLog("🔍 Checking userId values for ALL Core Data entities...")

        checkEntityUserId(Goal.self, entityName: "Goals", context: context)
        checkEntityUserId(GoalCategory.self, entityName: "Goal Categories", context: context)
        checkEntityUserId(TaskTimeWindow.self, entityName: "Task Time Windows", context: context)
        checkEntityUserId(WeightLog.self, entityName: "Weight Logs", context: context)
        checkEntityUserId(WorkoutLog.self, entityName: "Workout Logs", context: context)
        checkEntityUserId(FoodLog.self, entityName: "Food Logs", context: context)
        checkEntityUserId(WaterLog.self, entityName: "Water Logs", context: context)
        checkEntityUserId(CustomLogItem.self, entityName: "Custom Log Items", context: context)
        checkEntityUserId(CustomLogEntry.self, entityName: "Custom Log Entries", context: context)

        devLog("🔍 ============================================")
        devLog("💡 Check Console.app to see full results (filter by 'LotusPlannerV3')")
    }

    private func checkEntityUserId<T: NSManagedObject>(_ type: T.Type, entityName: String, context: NSManagedObjectContext) {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        do {
            let entities = try context.fetch(request)
            devLog("🔍 \(entityName): Found \(entities.count) total")
            if entities.isEmpty {
                devLog("   ℹ️ No data to check")
                return
            }
            var defaultCount = 0
            var icloudCount = 0
            var nilCount = 0
            var otherCount = 0
            for entity in entities {
                if let userIdValue = entity.value(forKey: "userId") as? String {
                    if userIdValue == "default" {
                        defaultCount += 1
                    } else if userIdValue == "icloud-user" {
                        icloudCount += 1
                    } else {
                        otherCount += 1
                    }
                } else {
                    nilCount += 1
                }
            }
            devLog("   - icloud-user: \(icloudCount) \(icloudCount == entities.count ? "✅" : "⚠️")")
            devLog("   - default: \(defaultCount) \(defaultCount > 0 ? "❌" : "")")
            devLog("   - nil: \(nilCount) \(nilCount > 0 ? "❌" : "")")
            devLog("   - other: \(otherCount) \(otherCount > 0 ? "❓" : "")")
        } catch {
            devLog("❌ Error checking \(entityName): \(error)")
        }
    }

    private func fixAllDataUserIds() {
        let context = PersistenceController.shared.container.viewContext
        devLog("🔧 ========== FIXING ALL DATA USERIDS ==========")
        devLog("🔧 Setting userId='icloud-user' on ALL entities...")

        var totalFixed = 0
        totalFixed += fixEntityUserId(Goal.self, entityName: "Goals", context: context)
        totalFixed += fixEntityUserId(GoalCategory.self, entityName: "Goal Categories", context: context)
        totalFixed += fixEntityUserId(TaskTimeWindow.self, entityName: "Task Time Windows", context: context)
        totalFixed += fixEntityUserId(WeightLog.self, entityName: "Weight Logs", context: context)
        totalFixed += fixEntityUserId(WorkoutLog.self, entityName: "Workout Logs", context: context)
        totalFixed += fixEntityUserId(FoodLog.self, entityName: "Food Logs", context: context)
        totalFixed += fixEntityUserId(WaterLog.self, entityName: "Water Logs", context: context)
        totalFixed += fixEntityUserId(CustomLogItem.self, entityName: "Custom Log Items", context: context)
        totalFixed += fixEntityUserId(CustomLogEntry.self, entityName: "Custom Log Entries", context: context)

        if context.hasChanges {
            do {
                try context.save()
                devLog("✅ Fixed \(totalFixed) entities - changes saved to Core Data")
                devLog("☁️ Changes will sync to CloudKit automatically")
                Task {
                    await MainActor.run {
                        iCloudManagerInstance.forceCompleteSync()
                        devLog("🔄 Triggered CloudKit sync")
                    }
                }
            } catch {
                devLog("❌ Error saving changes: \(error)")
            }
        } else {
            devLog("ℹ️ No changes needed - all data already correct")
        }
        devLog("🔧 ============================================")
    }

    private func fixEntityUserId<T: NSManagedObject>(_ type: T.Type, entityName: String, context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        do {
            let entities = try context.fetch(request)
            var fixedCount = 0
            for entity in entities {
                let currentUserId = entity.value(forKey: "userId") as? String
                if currentUserId != "icloud-user" {
                    entity.setValue("icloud-user", forKey: "userId")
                    fixedCount += 1
                }
            }
            if fixedCount > 0 {
                devLog("🔧 \(entityName): Fixed \(fixedCount)/\(entities.count)")
            } else {
                devLog("✅ \(entityName): All correct (\(entities.count) entities)")
            }
            return fixedCount
        } catch {
            devLog("❌ Error fixing \(entityName): \(error)")
            return 0
        }
    }

    private func checkCloudKitRawData() async {
        devLog("☁️ ========== QUERYING CLOUDKIT PRODUCTION ==========")
        let container = CKContainer(identifier: "iCloud.com.chenchungwan.LotusPlannerV3")
        let database = container.privateCloudDatabase

        do {
            let status = try await container.accountStatus()
            devLog("☁️ Account Status: \(status.rawValue) \(status == .available ? "✅" : "❌")")
            guard status == .available else {
                devLog("❌ Cannot query CloudKit - account not available")
                return
            }
        } catch {
            devLog("❌ Error checking account: \(error)")
            return
        }

        let recordTypes = ["CD_Goal", "CD_GoalCategory", "CD_TaskTimeWindow", "CD_WeightLog", "CD_WorkoutLog", "CD_FoodLog"]
        for recordType in recordTypes {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            do {
                let (results, _) = try await database.records(matching: query, resultsLimit: 100)
                var successCount = 0
                var failCount = 0
                for (_, result) in results {
                    switch result {
                    case .success: successCount += 1
                    case .failure: failCount += 1
                    }
                }
                devLog("☁️ \(recordType): \(successCount) records in CloudKit \(successCount > 0 ? "✅" : "⚠️")")
                if failCount > 0 {
                    devLog("   ⚠️ \(failCount) failed to fetch")
                }
            } catch {
                devLog("❌ Error querying \(recordType): \(error)")
            }
        }
        devLog("☁️ ============================================")
    }

    private func forceExportToCloudKit() {
        devLog("📤 ========== FORCE EXPORT TO CLOUDKIT ==========")
        let context = PersistenceController.shared.container.viewContext

        var totalTouched = 0
        totalTouched += touchAllEntities(Goal.self, entityName: "Goals", context: context)
        totalTouched += touchAllEntities(GoalCategory.self, entityName: "Goal Categories", context: context)
        totalTouched += touchAllEntities(TaskTimeWindow.self, entityName: "Task Time Windows", context: context)
        totalTouched += touchAllEntities(WeightLog.self, entityName: "Weight Logs", context: context)
        totalTouched += touchAllEntities(WorkoutLog.self, entityName: "Workout Logs", context: context)
        totalTouched += touchAllEntities(FoodLog.self, entityName: "Food Logs", context: context)
        totalTouched += touchAllEntities(WaterLog.self, entityName: "Water Logs", context: context)
        totalTouched += touchAllEntities(CustomLogItem.self, entityName: "Custom Log Items", context: context)
        totalTouched += touchAllEntities(CustomLogEntry.self, entityName: "Custom Log Entries", context: context)

        if context.hasChanges {
            do {
                try context.save()
                devLog("✅ Touched \(totalTouched) entities and saved")
                Task {
                    await MainActor.run {
                        iCloudManagerInstance.forceCompleteSync()
                    }
                }
            } catch {
                devLog("❌ Error saving: \(error)")
            }
        } else {
            devLog("ℹ️ No changes to save")
        }
        devLog("📤 ============================================")
    }

    private func touchAllEntities<T: NSManagedObject>(_ type: T.Type, entityName: String, context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                if entity.entity.attributesByName["updatedAt"] != nil {
                    entity.setValue(Date(), forKey: "updatedAt")
                }
            }
            return entities.count
        } catch {
            devLog("❌ Error touching \(entityName): \(error)")
            return 0
        }
    }
}

#Preview {
    DiagnosticsView()
}
