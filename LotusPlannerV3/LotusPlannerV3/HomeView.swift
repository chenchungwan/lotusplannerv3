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
    case settings = "Settings"

    var id: String { rawValue }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            CalendarView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
