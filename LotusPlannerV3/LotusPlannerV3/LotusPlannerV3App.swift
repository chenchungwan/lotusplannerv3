//
//  LotusPlannerV3App.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI

// MARK: - Debug Helper (disabled for performance)
private func debugPrint(_ message: String) {
    // Debug printing disabled for performance
}

@main
struct LotusPlannerV3App: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appPrefs = AppPreferences.shared

    init() {
        // Keep noisy diagnostics available during development without forcing
        // verbose operational logs on for TestFlight/App Store users.
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "verboseLoggingEnabled")
        #endif

        // Validate configuration on app launch
        let configManager = ConfigurationManager.shared
        configManager.debugPrintConfigurationInfo()

        if !configManager.validateConfiguration() {
        }

        guard !AppEnvironment.isRunningTests else { return }

        // Force iCloudManager to initialize (this will set up notification observers)
        _ = iCloudManager.shared

        // Start syncing the custom day view library (all named versions +
        // active selection) across devices via iCloud KVS.
        CustomDayViewLibrary.startSync()
        WeeklySummaryConfig.startSync()

        // Same KVS sync wiring for task recurrence rules. Rules created on
        // one device replicate to others without any extra work.
        RecurrenceLibrary.startSync()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appPrefs)
                .preferredColorScheme(appPrefs.isDarkMode ? .dark : .light)
        }

        #if targetEnvironment(macCatalyst)
        // The custom day-view configurator needs a real, resizable window to
        // be usable. Under Mac Catalyst's Mac idiom .fullScreenCover collapses
        // to a too-small modal sheet, so on Mac we open it as its own window
        // via openWindow(id:value:) from SettingsView. iOS still uses the
        // .fullScreenCover path.
        WindowGroup("Customize Day View", id: "configurator", for: UUID.self) { $versionId in
            if let versionId {
                DayViewCustomConfigurator(versionId: versionId)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(appPrefs)
                    .preferredColorScheme(appPrefs.isDarkMode ? .dark : .light)
            }
        }
        .defaultSize(width: 1280, height: 820)

        WindowGroup("Customize Weekly Summary", id: "weekly-summary-configurator") {
            WeeklySummaryConfigurator()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appPrefs)
                .preferredColorScheme(appPrefs.isDarkMode ? .dark : .light)
        }
        .defaultSize(width: 1100, height: 720)

        #endif
    }
}
