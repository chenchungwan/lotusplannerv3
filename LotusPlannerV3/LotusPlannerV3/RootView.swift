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

    var body: some View {
        ZStack(alignment: .leading) {
            // Underlying home view
            ContentView()
                .environment(\.managedObjectContext, viewContext)
                .disabled(!isCoverOpened) // Disable interaction until cover removed

            // Cover image overlay
            if !isCoverOpened {
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
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        coverOffset = -screenWidth
                                    }
                                    // Remove the cover after the slide-out animation finishes
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isCoverOpened = true
                                    }
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
            }
        }
    }
}

#Preview {
    // Use an in-memory context for preview
    let context = PersistenceController.preview.container.viewContext
    return RootView().environment(\.managedObjectContext, context)
} 