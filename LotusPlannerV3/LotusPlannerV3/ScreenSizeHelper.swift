import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Screen dimensions resolved through the app's active window scene.
///
/// `UIScreen.main` is deprecated because an app can span multiple displays and
/// resizable windows, so there is no single "main" screen. Scene lookup is the
/// supported replacement, but it yields nothing until the first scene connects
/// — which happens after singletons created during `@main` startup initialize.
/// To keep those callers working, the last resolved size is persisted and used
/// as a bootstrap value on the next launch.
enum ScreenMetrics {
    private static let lastKnownWidthKey = "screenMetrics.lastKnownWidth"
    private static let lastKnownHeightKey = "screenMetrics.lastKnownHeight"

    static var size: CGSize {
        if let live = liveSize {
            rememberSize(live)
            return live
        }
        return lastKnownSize ?? bootstrapSize
    }

    static var bounds: CGRect { CGRect(origin: .zero, size: size) }
    static var width: CGFloat { size.width }
    static var height: CGFloat { size.height }

    /// Size reported by the scene currently on screen, or `nil` before any
    /// scene has connected.
    private static var liveSize: CGSize? {
        #if canImport(UIKit)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
        guard let size = scene?.screen.bounds.size, size != .zero else { return nil }
        return size
        #elseif canImport(AppKit)
        return NSScreen.main?.frame.size
        #else
        return nil
        #endif
    }

    private static var lastKnownSize: CGSize? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: lastKnownWidthKey) != nil else { return nil }
        let size = CGSize(
            width: defaults.double(forKey: lastKnownWidthKey),
            height: defaults.double(forKey: lastKnownHeightKey)
        )
        return size == .zero ? nil : size
    }

    private static func rememberSize(_ size: CGSize) {
        guard lastKnownSize != size else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(size.width), forKey: lastKnownWidthKey)
        defaults.set(Double(size.height), forKey: lastKnownHeightKey)
    }

    /// Only reached on the very first launch, before a scene exists and before
    /// any real size has been recorded. These are starting points for draggable
    /// dividers, so being approximate is acceptable.
    private static var bootstrapSize: CGSize {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
            ? CGSize(width: 390, height: 844)
            : CGSize(width: 1024, height: 1366)
        #else
        return CGSize(width: 1920, height: 1080)
        #endif
    }
}

/// Observable wrapper so views can react to screen size changes.
@MainActor
class ScreenSizeHelper: ObservableObject {
    static let shared = ScreenSizeHelper()
    
    @Published var screenSize: CGSize = ScreenMetrics.size
    
    private init() {
        #if canImport(UIKit)
        // A scene activating or the device rotating are the two moments the
        // reported size can change. `UIScreen.didConnectNotification` used to
        // cover this but is deprecated in favor of scene-level notifications.
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScreenSize() }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScreenSize() }
        }
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func updateScreenSize() {
        let newSize = ScreenMetrics.size
        guard newSize != screenSize else { return }
        screenSize = newSize
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
