//
//  ContentView.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI

// MARK: - Conditional Sidebar Toggle Modifier
struct SidebarToggleConditional: ViewModifier {
    let hideToggle: Bool
    
    func body(content: Content) -> some View {
        if hideToggle {
            if #available(iOS 17, macOS 14, *) {
                content.toolbar(removing: .sidebarToggle)
            } else {
                content.toolbar(.hidden, for: .navigationBar)
            }
        } else {
            content
        }
    }
}

// MARK: - Sidebar Menu Items
private enum MenuItem: String, CaseIterable, Identifiable, Hashable {
    case calendar = "Calendars"
    case tasks = "Tasks"
    case goals = "Goals"
    case settings = "Settings"

    var id: String { rawValue }
}

struct ContentView: View {
    // Current selection in the sidebar
    @State private var selection: MenuItem = .calendar
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    var body: some View {
        Group {
            if #available(iOS 17, macOS 14, *) {
                // Use columnVisibility binding and drive detail via local state
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    detailView(for: selection)
                }
                .modifier(SidebarToggleConditional(hideToggle: appPrefs.hideLeftPanel))
            } else {
                // Fallback for iPadOS 16: non-selection initializer
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailView(for: selection)
                }
            }
        }
        .onChange(of: selection) {
            // Auto-close sidebar when user selects a menu item
            if #available(iOS 17, macOS 14, *) {
                columnVisibility = appPrefs.hideLeftPanel ? .detailOnly : .automatic
            }
        }
        .onChange(of: appPrefs.hideLeftPanel) {
            // Update sidebar visibility when setting changes
            if #available(iOS 17, macOS 14, *) {
                columnVisibility = appPrefs.hideLeftPanel ? .detailOnly : .automatic
            }
        }
        .onAppear {
            // Set initial sidebar visibility based on preference
            if #available(iOS 17, macOS 14, *) {
                columnVisibility = appPrefs.hideLeftPanel ? .detailOnly : .automatic
            }
        }
    }

    // MARK: - Extracted subviews
    private var sidebar: some View {
        List(MenuItem.allCases, id: \.self) { item in
            Text(item.rawValue)
                .onTapGesture {
                    selection = item
                }
        }
        .navigationTitle("Lotus Planner")
    }

    @ViewBuilder
    private func detailView(for item: MenuItem) -> some View {
        switch item {
        case .calendar:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                CalendarView()
            }
        case .tasks:
            // Respect navigation manager toggle between Calendar and Tasks
            if navigationManager.showTasksView {
                TasksView()
            } else {
                CalendarView()
            }
        case .goals:
            GoalsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
