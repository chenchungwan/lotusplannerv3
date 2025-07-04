import SwiftUI

/// A view modifier that removes the automatic sidebar toggle button from a view's navigation bar while still allowing the edge swipe gesture to reveal the sidebar.
struct SidebarToggleHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            // Earlier OS versions don't support removing a specific toolbar item,
            // but hiding the entire navigation bar removes the button while keeping
            // the drag gesture. Titles are not used in our detail views, so it's acceptable.
            content.toolbar(.hidden, for: .navigationBar)
        }
    }
}

extension View {
    /// Removes the sidebar toggle button from the navigation bar but keeps the swipe gesture.
    func sidebarToggleHidden() -> some View {
        self.modifier(SidebarToggleHidden())
    }
} 