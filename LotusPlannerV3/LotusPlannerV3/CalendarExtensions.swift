//
//  CalendarExtensions.swift
//  LotusPlannerV3
//
//  Created by refactoring from CalendarView.swift
//

import Foundation
import SwiftUI

// MARK: - Calendar Extensions

// Custom calendar that starts week on Monday
extension Calendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday = 2, Sunday = 1
        return calendar
    }
}

// Extension for custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
