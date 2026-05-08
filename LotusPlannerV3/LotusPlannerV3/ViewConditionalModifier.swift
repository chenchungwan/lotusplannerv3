import SwiftUI

// MARK: - Conditional Modifier

extension View {
    /// Applies `transform` to the view only when `condition` is true.
    /// Mirrors a common ViewModifier pattern that's awkward to express
    /// inline in SwiftUI without an `if` wrapper around the entire view.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
