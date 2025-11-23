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
        print("🚀 App: Initializing LotusPlannerV3...")
        
        // Validate configuration on app launch
        let configManager = ConfigurationManager.shared
        configManager.debugPrintConfigurationInfo()
        
        if !configManager.validateConfiguration() {
            #if DEBUG
            debugPrint("⚠️ Configuration validation failed")
            #endif
        }
        
        // Force iCloudManager to initialize (this will set up notification observers)
        _ = iCloudManager.shared
        
        print("✅ App: Initialization complete")
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
