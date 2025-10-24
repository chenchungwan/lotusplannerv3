import SwiftUI
import UIKit

/// Helper class to provide screen dimensions without using deprecated UIScreen.main
@MainActor
class ScreenSizeHelper: ObservableObject {
    static let shared = ScreenSizeHelper()
    
    @Published var screenSize: CGSize = .zero
    
    private init() {
        updateScreenSize()
        
        // Listen for screen size changes (device rotation, etc.)
        NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateScreenSize()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateScreenSize()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func updateScreenSize() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            screenSize = windowScene.screen.bounds.size
        } else {
            // Fallback to main screen if window scene is not available
            screenSize = UIScreen.main.bounds.size
        }
    }
    
    var screenWidth: CGFloat {
        screenSize.width
    }
    
    var screenHeight: CGFloat {
        screenSize.height
    }
}

/// View modifier to get screen dimensions
struct ScreenSizeModifier: ViewModifier {
    @StateObject private var screenHelper = ScreenSizeHelper.shared
    
    func body(content: Content) -> some View {
        content
            .environment(\.screenSize, screenHelper.screenSize)
            .environment(\.screenWidth, screenHelper.screenWidth)
            .environment(\.screenHeight, screenHelper.screenHeight)
    }
}

/// Environment keys for screen dimensions
private struct ScreenSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

private struct ScreenWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct ScreenHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var screenSize: CGSize {
        get { self[ScreenSizeKey.self] }
        set { self[ScreenSizeKey.self] = newValue }
    }
    
    var screenWidth: CGFloat {
        get { self[ScreenWidthKey.self] }
        set { self[ScreenWidthKey.self] = newValue }
    }
    
    var screenHeight: CGFloat {
        get { self[ScreenHeightKey.self] }
        set { self[ScreenHeightKey.self] = newValue }
    }
}

extension View {
    /// Add screen size tracking to any view
    func trackScreenSize() -> some View {
        modifier(ScreenSizeModifier())
    }
}
