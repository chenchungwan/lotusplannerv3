//
//  ContentView.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 7/1/25.
//

import SwiftUI

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
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    @ObservedObject private var navigationManager = NavigationManager.shared

    var body: some View {
        Group {
            if #available(iOS 17, macOS 14, *) {
                // Use columnVisibility binding and drive detail via local state
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    detailView(for: selection)
                }
                .toolbar(removing: .sidebarToggle)
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
                columnVisibility = .detailOnly
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
