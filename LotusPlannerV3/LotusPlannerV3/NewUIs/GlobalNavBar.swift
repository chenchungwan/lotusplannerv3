//
//  GlobalNavBar.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 9/11/25.
//

import SwiftUI

struct GlobalNavBar: View {
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let isNarrow = geo.size.width < 380
                VStack(alignment: .leading, spacing: isNarrow ? 6 : 0) {
                    HStack(alignment: .center, spacing: 8) {
                        Menu {
                            Button("Settings", action: { print("Option 1 selected") })
                            Button("About", action: { print("Option 2 selected") })
                            Button("Feedback", action: { print("Option 3 selected") })
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        Button { print("go back a day") } label: {
                            Image(systemName: "chevron.backward")
                        }
                        Text("Date/Date Range Label")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Button { print("go forward a day") } label: {
                            Image(systemName: "chevron.forward")
                        }
                        Spacer()
                        if !isNarrow {
                            Button { print("toggle hide completed") } label: {
                                Image(systemName: "eye.circle")
                            }
                            Button { print("refresh") } label: {
                                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            }
                            Menu("Add") {
                                Text("Event")
                                Text("Task")
                            }
                        }
                    }
                    if isNarrow {
                        HStack(spacing: 12) {
                            Button { print("toggle hide completed") } label: {
                                Image(systemName: "eye.circle")
                            }
                            Button { print("refresh") } label: {
                                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            }
                            Menu("Add") {
                                Text("Event")
                                Text("Task")
                            }
                            Spacer()
                        }
                    }
                    HStack {
                        Button { print("day") } label: { Image(systemName: "d.circle") }
                        Button { print("week") } label: { Image(systemName: "w.circle") }
                        Button { print("month") } label: { Image(systemName: "m.circle") }
                        Button { print("year") } label: { Image(systemName: "y.circle") }
                        Button { print("agenda") } label: { Image(systemName: "a.circle") }
                        Spacer()
                        Menu {
                            Button("Has Due Date", action: { print("Option 1 selected") })
                            Button("No Due Date", action: { print("Option 2 selected") })
                            Button("Overdue", action: { print("Option 3 selected") })
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .frame(height: 84)
        }
    }
}

    
    #Preview {
        GlobalNavBar()
    }
