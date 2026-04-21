import SwiftUI

/// A blank day view the user configures themselves.
/// The global nav bar at the top is provided by CalendarView via
/// `.safeAreaInset(edge: .top)`, so this view renders only the body area.
struct DayViewCustom: View {
    @ObservedObject private var bulkEditManager: BulkEditManager

    var onEventTap: ((GoogleCalendarEvent) -> Void)?

    @State private var showingConfigurator = false
    /// Bumped when the configurator dismisses, so we re-read UserDefaults.
    @State private var configVersion: Int = 0

    private var savedConfig: CustomDayViewConfig? {
        _ = configVersion
        return CustomDayViewConfig.load()
    }

    private var isConfigured: Bool { savedConfig != nil }

    /// Configuration is only available on iPad for now — drag/drop UX hasn't
    /// been validated on Mac yet. When running as a "Designed for iPad" app on
    /// macOS, we show an instructional message instead of the Configure button.
    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }

    init(bulkEditManager: BulkEditManager, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.onEventTap = onEventTap
    }

    var body: some View {
        Group {
            if isConfigured {
                // Live rendering of saved layout with real data is a follow-up;
                // for now we just confirm a layout has been saved so the "go
                // live" transition is visible.
                savedLayoutPlaceholder
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .fullScreenCover(isPresented: $showingConfigurator, onDismiss: {
            configVersion &+= 1
        }) {
            DayViewCustomConfigurator()
        }
    }

    private var savedLayoutPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Custom layout saved")
                .font(.title3)
                .foregroundColor(.primary)

            Text("Live rendering of the saved layout is coming soon. Your configuration is stored and ready.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !isRunningOnMac {
                Button {
                    showingConfigurator = true
                } label: {
                    Label("Reconfigure", systemImage: "slider.horizontal.3")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isRunningOnMac {
            macEmptyState
        } else {
            iPadEmptyState
        }
    }

    private var iPadEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Your custom day view is empty.")
                .font(.title3)
                .foregroundColor(.primary)

            Text("Drag and drop components into a 1- or 2-page layout to make it your own.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingConfigurator = true
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var macEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "ipad")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Configure on iPad first")
                .font(.title3)
                .foregroundColor(.primary)

            Text("The custom day view configuration is currently only supported on iPad. Set up your layout on iPad and it'll appear here once saved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    DayViewCustom(bulkEditManager: BulkEditManager())
}
