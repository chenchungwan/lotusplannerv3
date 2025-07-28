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
    @State private var isCoverOpened = false
    // Auto-dismiss timer
    @State private var autoSkipTimer: Timer?

    var body: some View {
        ZStack(alignment: .leading) {
            // Underlying home view
            ContentView()
                .environment(\.managedObjectContext, viewContext)
                .disabled(!isCoverOpened) // Disable interaction until cover removed

            // Cover image overlay
            if !isCoverOpened {
                ZStack {
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
                    
                    // Tap to skip overlay
                    VStack {
                        Spacer()
                        
                        Button(action: {
                            dismissCover()
                        }) {
                            HStack {
                                Text("TAP HERE TO SKIP")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(25)
                            .shadow(radius: 10)
                        }
                        .padding(.bottom, 50)
                    }
                    .ignoresSafeArea()
                }
                .onAppear {
                    startAutoSkipTimer()
                }
                .onDisappear {
                    stopAutoSkipTimer()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func dismissCover() {
        stopAutoSkipTimer()
        let screenWidth = UIScreen.main.bounds.width
        withAnimation(.easeOut(duration: 0.3)) {
            coverOffset = -screenWidth
        }
        // Remove the cover after the slide-out animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isCoverOpened = true
        }
    }
    
    private func startAutoSkipTimer() {
        // Auto-skip after 5 seconds
        autoSkipTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            print("🕐 Auto-skipping cover after 5 seconds")
            dismissCover()
        }
    }
    
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