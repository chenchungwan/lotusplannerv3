//
//  LotusPlannerV3App.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI

@main
struct LotusPlannerV3App: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appPrefs = AppPreferences.shared

    init() {
        // Validate configuration on app launch
        let configManager = ConfigurationManager.shared
        configManager.printConfigurationInfo()
        
        if !configManager.validateConfiguration() {
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appPrefs)
                .preferredColorScheme(appPrefs.isDarkMode ? .dark : .light)
        }
    }
}
