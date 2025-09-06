import SwiftUI
import CoreData
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct RootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // Horizontal offset for the cover image while dragging
    @State private var coverOffset: CGFloat = 0
    // Whether the cover has fully opened and should be dismissed
    @State private var isCoverOpened = false // Restore normal cover behavior
    // Auto-dismiss timer
    @State private var autoSkipTimer: Timer?

    var body: some View {
        ZStack(alignment: .leading) {
            // Underlying home view - always rendered and ready
            ContentView()
                .environment(\.managedObjectContext, viewContext)
                .opacity(isCoverOpened ? 1.0 : 0.0) // Fade in after cover dismisses
                .disabled(!isCoverOpened) // Disable interaction until cover removed

            // Cover image overlay
            if !isCoverOpened {
                ZStack {
                    // Solid background to prevent any system defaults from showing
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    // Fallback background in case image doesn't load
                    Rectangle()
                        .fill(Color.blue.gradient)
                        .ignoresSafeArea()

                    // Try to load cover image, but don't break if it fails
                    Image("CoverImage")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .offset(x: coverOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Allow dragging only from right to left (negative translation)
                                    if value.translation.width < 0 {
                                        coverOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    let screenWidth = UIScreen.main.bounds.width
                                    // If dragged more than 25% of width, complete opening
                                    if value.translation.width < -screenWidth * 0.25 {
                                        dismissCover()
                                    } else {
                                        // Otherwise, snap back to closed position
                                        withAnimation {
                                            coverOffset = 0
                                        }
                                    }
                                }
                        )
                        // Keep the sliding animation in sync with state changes
                        .animation(.interactiveSpring(), value: coverOffset)

                    // Removed Tap-to-Skip button overlay per requirement
                }
                .onAppear {
                    startAutoSkipTimer()
                }
                .onDisappear {
                    stopAutoSkipTimer()
                }
            }
        }
        .background(Color(.systemBackground)) // Ensure no system defaults show through
    }

    // MARK: - Helper Methods
    @MainActor
    private func dismissCover() {
        stopAutoSkipTimer()
        let screenWidth = UIScreen.main.bounds.width

        // Set navigation state immediately (ContentView is already rendered)
        let navigationManager = NavigationManager.shared
        navigationManager.switchToCalendar()
        navigationManager.updateInterval(.day, date: Date())

        withAnimation(.easeOut(duration: 0.3)) {
            coverOffset = -screenWidth
        }

        // Remove the cover after the slide-out animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeIn(duration: 0.01)) {
                self.isCoverOpened = true
            }
        }
    }
    
    @MainActor
    private func startAutoSkipTimer() {
        // Auto-skip after 5 seconds
        autoSkipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task { @MainActor in
                dismissCover()
            }
        }
    }

    @MainActor
    private func stopAutoSkipTimer() {
        autoSkipTimer?.invalidate()
        autoSkipTimer = nil
    }
}

#Preview {
    // Use an in-memory context for preview
    let context = PersistenceController.preview.container.viewContext
    return RootView().environment(\.managedObjectContext, context)
} 
