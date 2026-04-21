import SwiftUI
import UIKit
import Photos

@MainActor
enum PrintDayHelper {
    /// Snapshots the current visible window (including the nav bar) and writes it to the Photos library.
    static func saveCurrentWindowToPhotos(jobName: String) {
        guard let window = keyWindow(), let image = snapshotWindow(window) else { return }
        saveToPhotos(image, jobName: jobName)
    }

    /// Like `saveCurrentWindowToPhotos`, but when a scroll view has content taller (or wider)
    /// than its viewport, programmatically scrolls + snapshots + stitches so the off-screen
    /// content appears in the final image.
    static func saveExpandedWindowToPhotos(jobName: String) {
        guard let window = keyWindow() else { return }
        let innerV = findPreferredVerticalScrollView(in: window)
        let image: UIImage?
        if let innerV = innerV {
            image = stitchVerticalAndComposite(window: window, innerVertical: innerV)
        } else {
            image = snapshotWindow(window)
        }
        guard let image = image else { return }
        saveToPhotos(image, jobName: jobName)
    }

    /// Scroll view with vertical overflow that has the largest content height (weekly view's
    /// inner vertical scroll view wins over small nested scrollers).
    private static func findPreferredVerticalScrollView(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var bestHeight: CGFloat = 0
        var queue: [UIView] = [view]
        while !queue.isEmpty {
            let v = queue.removeFirst()
            if let sv = v as? UIScrollView,
               sv.contentSize.height > sv.bounds.height + 0.5,
               sv.contentSize.height > bestHeight {
                best = sv
                bestHeight = sv.contentSize.height
            }
            queue.append(contentsOf: v.subviews)
        }
        return best
    }

    /// Stitches the full vertical content of `innerVertical` by scrolling + snapshotting in
    /// slices, then composites the nav bar / above-scroll region on top and any below-scroll
    /// region at the bottom.
    /// Finds the scroll view's primary content subview — the one with bounds that match
    /// `contentSize`. UIScrollView holds this content view regardless of the current
    /// contentOffset; rendering it captures the *full* scrollable content in one pass,
    /// avoiding stitch seams from programmatic scrolling.
    private static func primaryContentSubview(of scrollView: UIScrollView) -> UIView? {
        let target = scrollView.contentSize
        var best: UIView?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        for sub in scrollView.subviews {
            let name = String(describing: type(of: sub))
            if name.contains("Scroll") || name.contains("Indicator") { continue }
            // Score: how close is this subview's bounds to contentSize?
            let dw = abs(sub.bounds.width - target.width)
            let dh = abs(sub.bounds.height - target.height)
            let score = dw + dh
            if score < bestScore {
                best = sub
                bestScore = score
            }
        }
        return best
    }

    private static func stitchVerticalAndComposite(window: UIWindow, innerVertical: UIScrollView) -> UIImage? {
        let origOffset = innerVertical.contentOffset
        let origShowsV = innerVertical.showsVerticalScrollIndicator
        let origShowsH = innerVertical.showsHorizontalScrollIndicator
        let origBounces = innerVertical.bounces
        let origBouncesV = innerVertical.alwaysBounceVertical
        let origBouncesH = innerVertical.alwaysBounceHorizontal
        innerVertical.showsVerticalScrollIndicator = false
        innerVertical.showsHorizontalScrollIndicator = false
        innerVertical.bounces = false
        innerVertical.alwaysBounceVertical = false
        innerVertical.alwaysBounceHorizontal = false

        // Some iOS versions keep the indicator subview visible regardless of the flag,
        // especially during programmatic scrolling. Hide the indicator subviews directly.
        var hiddenIndicators: [(view: UIView, wasHidden: Bool)] = []
        for subview in innerVertical.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("ScrollIndicator") || name.contains("Scroller") {
                hiddenIndicators.append((subview, subview.isHidden))
                subview.isHidden = true
            }
        }

        let restore: () -> Void = {
            innerVertical.setContentOffset(origOffset, animated: false)
            innerVertical.showsVerticalScrollIndicator = origShowsV
            innerVertical.showsHorizontalScrollIndicator = origShowsH
            innerVertical.bounces = origBounces
            innerVertical.alwaysBounceVertical = origBouncesV
            innerVertical.alwaysBounceHorizontal = origBouncesH
            for (view, wasHidden) in hiddenIndicators { view.isHidden = wasHidden }
        }

        innerVertical.setContentOffset(.zero, animated: false)
        innerVertical.layoutIfNeeded()
        CATransaction.flush()

        guard let baseline = snapshotWindow(window) else {
            restore()
            return nil
        }

        let innerFrame = innerVertical.convert(innerVertical.bounds, to: window)
        let aboveH = max(0, innerFrame.origin.y)
        let belowH = max(0, window.bounds.height - innerFrame.maxY)
        let viewportH = innerFrame.height
        let contentH = innerVertical.contentSize.height
        let maxOffsetY = max(0, contentH - viewportH)

        let finalWidth = window.bounds.width
        let finalHeight = aboveH + contentH + belowH
        let finalSize = CGSize(width: finalWidth, height: finalHeight)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            // Above area (nav bar, header) from baseline.
            if aboveH > 0,
               let cg = baseline.cgImage?.cropping(to: CGRect(
                x: 0, y: 0,
                width: baseline.size.width * baseline.scale,
                height: aboveH * baseline.scale
               )) {
                UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
                    .draw(in: CGRect(x: 0, y: 0, width: baseline.size.width, height: aboveH))
            }

            // Render the scroll view's content subview directly at its full bounds.
            // This avoids the stitch-seam artifacts from scroll-and-snapshot loops.
            if let contentView = primaryContentSubview(of: innerVertical) {
                let contentBounds = contentView.bounds
                let contentImage = UIGraphicsImageRenderer(size: contentBounds.size).image { _ in
                    contentView.drawHierarchy(in: contentBounds, afterScreenUpdates: true)
                }
                contentImage.draw(in: CGRect(
                    x: innerFrame.origin.x,
                    y: aboveH,
                    width: innerFrame.width,
                    height: contentH
                ))
            } else {
                // Fallback: draw whatever is currently visible in the viewport.
                let currentFrame = innerVertical.convert(innerVertical.bounds, to: window)
                if let cg = baseline.cgImage?.cropping(to: CGRect(
                    x: currentFrame.origin.x * baseline.scale,
                    y: currentFrame.origin.y * baseline.scale,
                    width: currentFrame.width * baseline.scale,
                    height: viewportH * baseline.scale
                )) {
                    UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
                        .draw(in: CGRect(
                            x: currentFrame.origin.x,
                            y: aboveH,
                            width: currentFrame.width,
                            height: viewportH
                        ))
                }
                _ = maxOffsetY
            }

            // Below area from baseline.
            if belowH > 0,
               let cg = baseline.cgImage?.cropping(to: CGRect(
                x: 0,
                y: innerFrame.maxY * baseline.scale,
                width: baseline.size.width * baseline.scale,
                height: belowH * baseline.scale
               )) {
                UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
                    .draw(in: CGRect(
                        x: 0,
                        y: aboveH + contentH,
                        width: baseline.size.width,
                        height: belowH
                    ))
            }
        }

        restore()
        innerVertical.layoutIfNeeded()

        return image
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
    }

    private static func snapshotWindow(_ window: UIWindow) -> UIImage? {
        let bounds = window.bounds
        guard bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private static func saveToPhotos(_ image: UIImage, jobName: String) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetCreationRequest.creationRequestForAsset(from: image)
                    }, completionHandler: { success, error in
                        DispatchQueue.main.async {
                            presentResultAlert(success: success, error: error, jobName: jobName)
                        }
                    })
                case .denied, .restricted:
                    presentPermissionDeniedAlert()
                default:
                    break
                }
            }
        }
    }

    private static func topmostViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    private static func presentResultAlert(success: Bool, error: Error?, jobName: String) {
        let title = success ? "Saved to Photos" : "Couldn’t Save"
        let message = success ? "\(jobName) was saved to your Photos." : (error?.localizedDescription ?? "An unknown error occurred.")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topmostViewController()?.present(alert, animated: true)
    }

    private static func presentPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Photos Access Needed",
            message: "Enable Photos access for Lotus Planner in Settings to save snapshots.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        topmostViewController()?.present(alert, animated: true)
    }
}

struct GlobalNavBar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var logsVM = LogsViewModel.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Sheet states
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingReportIssues = false
    @State private var showingDatePicker = false
    @State private var showingAddEvent = false
    @State private var showingAddTask = false
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingAddLog = false

    // Sync state
    @State private var isSyncing = false

    // Date picker state
    @State private var selectedDateForPicker = Date()
    
    // Device-specific computed properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }
    
    private var shouldShowTwoRows: Bool {
        isCompact && isPortrait
    }
    
    private var adaptivePadding: CGFloat {
        isCompact ? 8 : 12
    }
    
    private var adaptiveButtonSpacing: CGFloat {
        isCompact ? 8 : 10
    }
    
    private var adaptiveIconSize: Font {
        isCompact ? .body : .title2
    }
    
    private var adaptiveButtonSize: CGFloat {
        isCompact ? 36 : 44
    }

    /// Treat bookView the same as calendar for nav bar layout purposes
    private var isCalendarLikeView: Bool {
        navigationManager.currentView == .calendar || navigationManager.currentView == .bookView
    }

    private var dateLabel: String {
        // Show "Task Lists" when in Lists view
        if navigationManager.currentView == .lists {
            return "Task Lists"
        }
        
        // Show filtered goals title when in Goals view
        if navigationManager.currentView == .goals {
            switch navigationManager.currentInterval {
            case .day:
                return "All Goals"
            case .week:
                guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
                    return "Goals"
                }
                let start = weekInterval.start
                let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
                let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d"
                let startString = dateFormatter.string(from: start)
                let endString = dateFormatter.string(from: end)
                return "W\(weekNumber): \(startString) - \(endString)"
            case .month:
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: navigationManager.currentDate)
            case .year:
                let year = Calendar.current.component(.year, from: navigationManager.currentDate)
                return "\(year)"
            }
        }
        
        // Show "All Tasks" when in Tasks view and showing all tasks
        if navigationManager.showTasksView && navigationManager.showingAllTasks {
            return "All Tasks"
        }
        
        // Show year when in yearly calendar view
        if navigationManager.currentView == .yearlyCalendar {
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year)"
        }
        
        switch navigationManager.currentInterval {
        case .year:
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year)"
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: navigationManager.currentDate)
        case .week:
            guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
                return ""
            }
            let start = weekInterval.start
            let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
            
            // Get week number
            let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
            
            // Format dates as M/d
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d"
            let startString = dateFormatter.string(from: start)
            let endString = dateFormatter.string(from: end)
            
            return "W\(weekNumber): \(startString) - \(endString)"
        case .day:
            let date = navigationManager.currentDate
            
            // Get day of week abbreviation
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            let dayOfWeek = dayFormatter.string(from: date).uppercased()
            
            // Format as M/d/yy
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy"
            let dateString = dateFormatter.string(from: date)
            
            return "\(dayOfWeek) \(dateString)"
        }
    }
    
    private var isCurrentPeriod: Bool {
        let now = Date()
        let currentDate = navigationManager.currentDate
        
        switch navigationManager.currentInterval {
        case .year:
            return Calendar.current.isDate(currentDate, equalTo: now, toGranularity: .year)
        case .month:
            return Calendar.current.isDate(currentDate, equalTo: now, toGranularity: .month)
        case .week:
            let mondayFirst = Calendar.mondayFirst
            guard let weekInterval = mondayFirst.dateInterval(of: .weekOfYear, for: currentDate),
                  let nowWeekInterval = mondayFirst.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }
            return weekInterval.start == nowWeekInterval.start
        case .day:
            return Calendar.current.isDate(currentDate, inSameDayAs: now)
        }
    }
    
    private func handleTimeIntervalChange(_ interval: TimelineInterval) {
        if navigationManager.currentView == .goals {
            navigationManager.updateInterval(interval, date: Date())
        } else if navigationManager.currentView == .bookView {
            // In Book View: always navigate to the current (today's) page
            let now = Date()
            let calendar = Calendar.current
            navigationManager.updateInterval(interval, date: now)
            switch interval {
            case .day:
                NotificationCenter.default.post(name: .bookViewNavigateToDay, object: now)
            case .week:
                NotificationCenter.default.post(name: .bookViewNavigateToWeek, object: now)
            case .month:
                let m = calendar.component(.month, from: now)
                let y = calendar.component(.year, from: now)
                NotificationCenter.default.post(name: .bookViewNavigateToMonth, object: [m, y])
            case .year:
                let y = calendar.component(.year, from: now)
                NotificationCenter.default.post(name: .bookViewNavigateToYear, object: y)
            }
        } else if navigationManager.showTasksView {
            // In Tasks view: filter to the interval
            navigationManager.showingAllTasks = false
            navigationManager.updateInterval(interval, date: Date())
        } else if navigationManager.currentView == .yearlyCalendar {
            // In Yearly Calendar view: switch to the new interval
            navigationManager.showingAllTasks = false
            if interval == .year {
                navigationManager.updateInterval(interval, date: Date())
                // Already in yearly view, just update interval
            } else {
                // Update interval first, then force view change
                navigationManager.updateInterval(interval, date: Date())

                // Use the existing switchToCalendar() function which should work properly
                navigationManager.switchToCalendar()
            }
        } else {
            // In Calendar view: go to the interval
            navigationManager.showingAllTasks = false
            if interval == .year {
                navigationManager.updateInterval(interval, date: Date())
                navigationManager.switchToYearlyCalendar()
            } else {
                // Update interval BEFORE switching view so switchToCalendar() sees the new interval
                navigationManager.updateInterval(interval, date: Date())
                navigationManager.switchToCalendar()
            }
        }
    }
    
    private func step(_ direction: Int) {
        // Handle Book View navigation: step within the current interval's page type
        if navigationManager.currentView == .bookView {
            let calendar = Calendar.current
            let component = navigationManager.currentInterval.calendarComponent
            guard let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) else { return }
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            switch navigationManager.currentInterval {
            case .day:
                NotificationCenter.default.post(name: .bookViewNavigateToDay, object: newDate)
            case .week:
                NotificationCenter.default.post(name: .bookViewNavigateToWeek, object: newDate)
            case .month:
                let m = calendar.component(.month, from: newDate)
                let y = calendar.component(.year, from: newDate)
                NotificationCenter.default.post(name: .bookViewNavigateToMonth, object: [m, y])
            case .year:
                let y = calendar.component(.year, from: newDate)
                NotificationCenter.default.post(name: .bookViewNavigateToYear, object: y)
            }
            return
        }

        // Handle year navigation when in yearly calendar view
        if navigationManager.currentView == .yearlyCalendar {
            if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: direction, to: navigationManager.currentDate) {
                navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            }
            return
        }
        
        // Handle journal day views navigation
        if navigationManager.currentView == .journalDayViews {
            let component = navigationManager.currentInterval.calendarComponent
            if let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
                // Update the navigation manager
                navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)

                // Post notification for journal content refresh
                NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
            }
            return
        }
        
        let component = navigationManager.currentInterval.calendarComponent
        if let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
            // First update the navigation
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            
            // Then do a comprehensive data refresh
            Task {
                // Clear all caches first
                calendarVM.clearAllData()
                await tasksVM.loadTasks(forceClear: true)
                
                // Load fresh data based on interval
                switch navigationManager.currentInterval {
                case .day:
                    await calendarVM.loadCalendarData(for: newDate)
                case .week:
                    await calendarVM.loadCalendarDataForWeek(containing: newDate)
                case .month:
                    await calendarVM.loadCalendarDataForMonth(containing: newDate)
                case .year:
                    await calendarVM.loadCalendarDataForMonth(containing: newDate)
                }
                
                // Force UI refresh
                await MainActor.run {
                    // Reload logs data
                    LogsViewModel.shared.reloadData()
                    
                    // Post notifications for UI updates
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
                    
                    // Force calendar refresh
                    calendarVM.objectWillChange.send()
                    tasksVM.objectWillChange.send()
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaLeading = geometry.safeAreaInsets.leading
            let safeAreaTrailing = geometry.safeAreaInsets.trailing
            let horizontalSafeInset = max(safeAreaLeading, safeAreaTrailing, 0)
            
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // First row: Main navigation
                HStack(spacing: isCompact ? 4 : adaptiveButtonSpacing) {
                    Menu {
                            Button(action: {
                                navigationManager.switchToCalendar()
                            }) {
                                Label("Calendar", systemImage: "calendar")
                            }
                            
                            Button(action: {
                                navigationManager.switchToTasks()
                            }) {
                                Label("Tasks", systemImage: "checklist")
                            }
                            
                            Button(action: {
                                navigationManager.switchToLists()
                            }) {
                                Label("Lists", systemImage: "list.bullet")
                            }
                            
                            Button(action: {
                                navigationManager.switchToJournalDayViews()
                            }) {
                                Label("Journals", systemImage: "book")
                            }

                            if !appPrefs.hideBookView {
                                Button(action: {
                                    navigationManager.switchToBookView()
                                }) {
                                    Label("Book View (Beta)", systemImage: "book.pages")
                                }
                            }

                            if !appPrefs.hideGoals {
                                Button(action: {
                                    navigationManager.switchToGoals()
                                }) {
                                    Label("Goals (Beta)", systemImage: "target")
                                }
                            }
                            Divider()
                            
                            Button(action: {
                                showingSettings = true
                            }) {
                                Label("Settings", systemImage: "gearshape")
                            }
                            Button(action: {
                                showingAbout = true
                            }) {
                                Label("About", systemImage: "info.circle")
                            }
                            Button(action: {
                                showingReportIssues = true
                            }) {
                                Label("Report Issue / Request Features", systemImage: "exclamationmark.bubble")
                            }

                            if let url = URL(string: "https://apps.apple.com/us/app/lotus-planner/id6749281062?action=write-review") {
                                Link(destination: url) {
                                    Label("Rate the App", systemImage: "star")
                                }
                            }

                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(adaptiveIconSize)
                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(-1) } label: {
                                Image(systemName: "chevron.left")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                        }
                        
                        Button {
                            // Only open date picker if not in Lists view or Goals All Goals view
                            if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                                selectedDateForPicker = navigationManager.currentDate
                                showingDatePicker = true
                            }
                        } label: {
                            Text(dateLabel)
                                .font(isCompact ? .headline : .title2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundColor(navigationManager.currentView == .lists || (navigationManager.showTasksView && navigationManager.showingAllTasks) || (navigationManager.currentView == .goals && navigationManager.currentInterval == .day) ? .primary : (isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : .primary))
                        }
                        .disabled(navigationManager.currentView == .lists || (navigationManager.currentView == .goals && navigationManager.currentInterval == .day))
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                        }
                        
                        Spacer()
                        
                        // Only show interval buttons in first row if NOT using two-row layout
                        if !shouldShowTwoRows {
                        // Show interval buttons in single row on all devices
                        // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // In Timebox View, show all buttons but highlight appropriate circle
                                if navigationManager.currentView == .timebox {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            handleTimeIntervalChange(.day)
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Button {
                                        handleTimeIntervalChange(.week)
                                    } label: {
                                        Image(systemName: "w.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(.secondary)
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            navigationManager.switchToTimebox()
                                        } label: {
                                            Image(systemName: "t.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.currentView == .timebox ? .accentColor : .secondary)
                                        }
                                    }
                                } else {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentDay"), object: nil)
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.day)
                                            }
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                        }
                                    }
                                    // Hide s.circle in Tasks view
                                    if navigationManager.currentView != .tasks {
                                        Button {
                                            // In other views: handle week interval change
                                            handleTimeIntervalChange(.week)
                                        } label: {
                                            Image(systemName: (isCalendarLikeView || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .goals) ? "w.circle" : "s.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week && !navigationManager.isShowingTimebox ? .accentColor : .secondary)))
                                        }
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentWeek"), object: nil)
                                            } else if navigationManager.currentView == .bookView {
                                                // In Book View: navigate to current week's timebox page
                                                navigationManager.updateInterval(.week, date: Date())
                                                NotificationCenter.default.post(name: .bookViewNavigateToTimebox, object: Date())
                                            } else if isCalendarLikeView || navigationManager.currentView == .yearlyCalendar {
                                                // In Calendar or Yearly Calendar view: switch to timebox view
                                                navigationManager.switchToTimebox()
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.week)
                                            }
                                        } label: {
                                            Image(systemName: (isCalendarLikeView || navigationManager.currentView == .yearlyCalendar) ? "t.circle" : "w.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentView == .timebox || navigationManager.isShowingTimebox ? .accentColor : .secondary)))
                                        }
                                    }
                                }
                                Button {
                                    if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                        // In Tasks view with All Tasks filter: send notification to ensure proper update
                                        NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentMonth"), object: nil)
                                    } else {
                                        handleTimeIntervalChange(.month)
                                    }
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                        // In Tasks view with All Tasks filter: send notification to ensure proper update
                                        NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentYear"), object: nil)
                                    } else {
                                        handleTimeIntervalChange(.year)
                                    }
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                            }
                            
                            // Only show action buttons in first row if NOT using two-row layout
                            if !shouldShowTwoRows {
                            
                            // Hide ellipsis.circle in calendar views, lists view, journal day views, and timebox view
                            if !isCalendarLikeView && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews && navigationManager.currentView != .timebox {
                                if navigationManager.currentView == .goals {
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    Menu {
                                        Button("All") {
                                            // Switch to "All" tasks view
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                        }
                                        Divider()
                                        Button("Has Due Date") {
                                            // Switch to All view with Has Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.hasDueDate)
                                        }
                                        Button("No Due Date") {
                                            // Switch to All view with No Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.noDueDate)
                                        }
                                        Button("Overdue") {
                                            // Switch to All view with Past Due filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.pastDue)
                                        }
                                        Button("Complete") {
                                            // Switch to All view with Complete filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.completed)
                                            // Turn off hide completed setting to show completed tasks
                                            appPrefs.updateHideCompletedTasks(false)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(adaptiveIconSize)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                if isSyncing {
                                    // Spinning wheel
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                } else {
                                    // Static combined icon
                                    Image(systemName: "arrow.trianglehead.clockwise.icloud")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                            .disabled(isSyncing)
                            .id(isSyncing)
                            
                            // Hide completed tasks toggle — shown but disabled in month/year views and journal day views
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .lists ||
                               isCalendarLikeView || navigationManager.currentView == .yearlyCalendar ||
                               navigationManager.currentView == .timebox || navigationManager.currentView == .journalDayViews {
                                let eyeInactive = navigationManager.currentView == .journalDayViews || ((isCalendarLikeView || navigationManager.currentView == .yearlyCalendar) && (navigationManager.currentInterval == .month || navigationManager.currentInterval == .year))
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(eyeInactive ? .secondary.opacity(0.4) : .accentColor)
                                }
                                .disabled(eyeInactive)
                            }

                            // Save snapshot to Photos (day and week calendar views, iPad/Mac only)
                            if navigationManager.currentView == .calendar &&
                                (navigationManager.currentInterval == .day || navigationManager.currentInterval == .week) &&
                                UIDevice.current.userInterfaceIdiom != .phone {
                                Button {
                                    let formatter = DateFormatter()
                                    if navigationManager.currentInterval == .week,
                                       let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) {
                                        formatter.dateFormat = "M/d"
                                        let start = formatter.string(from: weekInterval.start)
                                        let end = formatter.string(from: Calendar.mondayFirst.date(byAdding: .day, value: 6, to: weekInterval.start) ?? weekInterval.start)
                                        PrintDayHelper.saveExpandedWindowToPhotos(jobName: "Week \(start) – \(end)")
                                    } else {
                                        formatter.dateStyle = .medium
                                        PrintDayHelper.saveCurrentWindowToPhotos(jobName: "Day — \(formatter.string(from: navigationManager.currentDate))")
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle — shown but disabled in month/year views and journal day views
                            if isCalendarLikeView || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .journalDayViews {
                                let bulkInactive = navigationManager.currentView == .journalDayViews || navigationManager.currentInterval == .month || navigationManager.currentInterval == .year || navigationManager.currentView == .yearlyCalendar
                                Button {
                                    if navigationManager.currentView == .bookView {
                                        NotificationCenter.default.post(name: .toggleBookViewBulkEdit, object: nil)
                                    } else if navigationManager.currentInterval == .day {
                                        NotificationCenter.default.post(name: Notification.Name("ToggleCalendarBulkEdit"), object: nil)
                                    } else if navigationManager.currentInterval == .week {
                                        NotificationCenter.default.post(name: Notification.Name("ToggleWeeklyCalendarBulkEdit"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(bulkInactive ? .secondary.opacity(0.4) : .accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(bulkInactive)
                            }

                            // Bulk edit toggle (in Tasks view)
                            if navigationManager.currentView == .tasks {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTasksBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Lists view)
                            if navigationManager.currentView == .lists {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleListsBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Timebox view)
                            if navigationManager.currentView == .timebox {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTimeboxBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // + menu based on current view
                            if navigationManager.currentView == .journalDayViews {
                                // In Journal Day Views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .lists {
                                // In Lists view: menu with Event, Task, and List
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("List") {
                                        showingAddList = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .goals {
                                // In Goals view: menu with Event, Task, and Goal
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("Goal") {
                                        NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else {
                                // In other views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                            }
                    }
                    .padding(.horizontal, max(adaptivePadding + horizontalSafeInset, 4))
                    .padding(.top, 8)
                    .padding(.bottom, shouldShowTwoRows ? 2 : 8)
                    
                    // Second row on compact portrait devices: Interval and action buttons
                    if shouldShowTwoRows {
                        HStack(spacing: isCompact ? 4 : adaptiveButtonSpacing) {
                            // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // In Timebox View, show all buttons but highlight appropriate circle
                                if navigationManager.currentView == .timebox {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                        handleTimeIntervalChange(.day)
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Button {
                                        handleTimeIntervalChange(.week)
                                    } label: {
                                        Image(systemName: "w.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(.secondary)
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            navigationManager.switchToTimebox()
                                        } label: {
                                            Image(systemName: "t.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.currentView == .timebox ? .accentColor : .secondary)
                                        }
                                    }
                                } else {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentDay"), object: nil)
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.day)
                                            }
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                        }
                                    }
                                    // Hide s.circle in Tasks view
                                    if navigationManager.currentView != .tasks {
                                        Button {
                                            // In other views: handle week interval change
                                            handleTimeIntervalChange(.week)
                                        } label: {
                                            Image(systemName: (isCalendarLikeView || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .goals) ? "w.circle" : "s.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week && !navigationManager.isShowingTimebox ? .accentColor : .secondary)))
                                        }
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentWeek"), object: nil)
                                            } else if navigationManager.currentView == .bookView {
                                                // In Book View: navigate to current week's timebox page
                                                navigationManager.updateInterval(.week, date: Date())
                                                NotificationCenter.default.post(name: .bookViewNavigateToTimebox, object: Date())
                                            } else if isCalendarLikeView || navigationManager.currentView == .yearlyCalendar {
                                                // In Calendar or Yearly Calendar view: switch to timebox view
                                                navigationManager.switchToTimebox()
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.week)
                                            }
                                        } label: {
                                            Image(systemName: (isCalendarLikeView || navigationManager.currentView == .yearlyCalendar) ? "t.circle" : "w.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentView == .timebox || navigationManager.isShowingTimebox ? .accentColor : .secondary)))
                                        }
                                    }
                                }
                                Button {
                                    if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                        // In Tasks view with All Tasks filter: send notification to ensure proper update
                                        NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentMonth"), object: nil)
                                    } else {
                                        handleTimeIntervalChange(.month)
                                    }
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                        // In Tasks view with All Tasks filter: send notification to ensure proper update
                                        NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentYear"), object: nil)
                                    } else {
                                        handleTimeIntervalChange(.year)
                                    }
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                             
                            Spacer()
                            
                            // Hide ellipsis.circle in calendar views, lists view, journal day views, and timebox view
                            if !isCalendarLikeView && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews && navigationManager.currentView != .timebox {
                                if navigationManager.currentView == .goals {
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    Menu {
                                        Button("All") {
                                            // Switch to "All" tasks view
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                        }
                                        Divider()
                                        Button("Has Due Date") {
                                            // Switch to All view with Has Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.hasDueDate)
                                        }
                                        Button("No Due Date") {
                                            // Switch to All view with No Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.noDueDate)
                                        }
                                        Button("Overdue") {
                                            // Switch to All view with Past Due filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.pastDue)
                                        }
                                        Button("Complete") {
                                            // Switch to All view with Complete filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.completed)
                                            // Turn off hide completed setting to show completed tasks
                                            appPrefs.updateHideCompletedTasks(false)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(adaptiveIconSize)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                if isSyncing {
                                    // Spinning wheel
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                } else {
                                    // Static combined icon
                                    Image(systemName: "arrow.trianglehead.clockwise.icloud")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                            .disabled(isSyncing)
                            .id(isSyncing)
                            
                            // Hide completed tasks toggle — shown but disabled in month/year views and journal day views
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .lists ||
                               isCalendarLikeView || navigationManager.currentView == .yearlyCalendar ||
                               navigationManager.currentView == .timebox || navigationManager.currentView == .journalDayViews {
                                let eyeInactive = navigationManager.currentView == .journalDayViews || ((isCalendarLikeView || navigationManager.currentView == .yearlyCalendar) && (navigationManager.currentInterval == .month || navigationManager.currentInterval == .year))
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(eyeInactive ? .secondary.opacity(0.4) : .accentColor)
                                }
                                .disabled(eyeInactive)
                            }

                            // Save snapshot to Photos (day and week calendar views, iPad/Mac only)
                            if navigationManager.currentView == .calendar &&
                                (navigationManager.currentInterval == .day || navigationManager.currentInterval == .week) &&
                                UIDevice.current.userInterfaceIdiom != .phone {
                                Button {
                                    let formatter = DateFormatter()
                                    if navigationManager.currentInterval == .week,
                                       let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) {
                                        formatter.dateFormat = "M/d"
                                        let start = formatter.string(from: weekInterval.start)
                                        let end = formatter.string(from: Calendar.mondayFirst.date(byAdding: .day, value: 6, to: weekInterval.start) ?? weekInterval.start)
                                        PrintDayHelper.saveExpandedWindowToPhotos(jobName: "Week \(start) – \(end)")
                                    } else {
                                        formatter.dateStyle = .medium
                                        PrintDayHelper.saveCurrentWindowToPhotos(jobName: "Day — \(formatter.string(from: navigationManager.currentDate))")
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle — shown but disabled in month/year views and journal day views
                            if isCalendarLikeView || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .journalDayViews {
                                let bulkInactive = navigationManager.currentView == .journalDayViews || navigationManager.currentInterval == .month || navigationManager.currentInterval == .year || navigationManager.currentView == .yearlyCalendar
                                Button {
                                    if navigationManager.currentView == .bookView {
                                        NotificationCenter.default.post(name: .toggleBookViewBulkEdit, object: nil)
                                    } else if navigationManager.currentInterval == .day {
                                        NotificationCenter.default.post(name: Notification.Name("ToggleCalendarBulkEdit"), object: nil)
                                    } else if navigationManager.currentInterval == .week {
                                        NotificationCenter.default.post(name: Notification.Name("ToggleWeeklyCalendarBulkEdit"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(bulkInactive ? .secondary.opacity(0.4) : .accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(bulkInactive)
                            }

                            // Bulk edit toggle (in Tasks view)
                            if navigationManager.currentView == .tasks {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTasksBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Lists view)
                            if navigationManager.currentView == .lists {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleListsBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Timebox view)
                            if navigationManager.currentView == .timebox {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTimeboxBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // + menu based on current view
                            if navigationManager.currentView == .journalDayViews {
                                // In Journal Day Views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .lists {
                                // In Lists view: menu with Event, Task, and List
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("List") {
                                        showingAddList = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .goals {
                                // In Goals view: menu with Event, Task, and Goal
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("Goal") {
                                        NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else {
                                // In other views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                        }
                        .padding(.horizontal, max(adaptivePadding + horizontalSafeInset, 4))
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                }
                .frame(height: shouldShowTwoRows ? 100 : 50)
            }
        }
        .frame(height: shouldShowTwoRows ? 100 : 50)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingReportIssues) {
            ReportIssuesView()
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") { showingDatePicker = false },
                    trailing: Button("Done") {
                        // Navigate based on current view context
                        if navigationManager.showTasksView && navigationManager.showingAllTasks {
                            // If in Tasks view filtered to ALL, go to yearly view
                            navigationManager.updateInterval(.year, date: selectedDateForPicker)
                        } else {
                            // Otherwise, respect current interval but use selected date
                            navigationManager.updateInterval(navigationManager.currentInterval, date: selectedDateForPicker)
                        }
                        showingDatePicker = false
                    }
                )
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingAddEvent) {
            NavigationStack {
                AddItemView(
                    currentDate: navigationManager.currentDate,
                    tasksViewModel: tasksVM,
                    calendarViewModel: calendarVM,
                    appPrefs: appPrefs,
                    showEventOnly: true
                )
            }
        }
        .sheet(isPresented: $showingAddTask) {
            let personalLinked = auth.isLinked(kind: .personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? .personal : .professional
            let defaultLists = defaultAccount == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil,
                position: "0"
            )
            
            NavigationStack {
                TaskDetailsView(
                    task: newTask,
                    taskListId: defaultListId,
                    accountKind: defaultAccount,
                    accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updatedTask in
                        Task {
                            await tasksVM.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                        }
                    },
                    onDelete: {
                        // No-op for new task creation
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksVM.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        Task {
                            await tasksVM.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                        }
                    },
                    isNew: true
                )
            }
        }
        .sheet(isPresented: $showingAddList) {
            NewListSheet(
                appPrefs: appPrefs,
                accountKind: newListAccountKind,
                hasPersonal: auth.isLinked(kind: .personal),
                hasProfessional: auth.isLinked(kind: .professional),
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                listName: $newListName,
                selectedAccount: $newListAccountKind,
                onCreate: {
                    createNewList()
                }
            )
            .onAppear {
                // Reset state when sheet appears
                newListName = ""
                newListAccountKind = nil
            }
        }
        .sheet(isPresented: $showingAddLog) {
            AddLogEntryView(viewModel: logsVM)
        }
    }
    
    // MARK: - Create New List Function
    private func createNewList() {
        guard let accountKind = newListAccountKind else { return }
        
        Task {
            let _ = await tasksVM.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
            await MainActor.run {
                showingAddList = false
                newListName = ""
                newListAccountKind = nil
            }
        }
    }
    
    // MARK: - Data Reload Functions
    private func reloadAllData() async {
        // Start sync indicator
        await MainActor.run {
            isSyncing = true
        }

        // FIRST: Force iCloud/CloudKit sync to push/pull changes
        iCloudManager.shared.forceCompleteSync()

        // Wait for CloudKit to sync
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let currentDate = navigationManager.currentDate

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.goalsManager.refreshData()

        // Reload custom logs data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.customLogManager.refreshData()

        // Wait for CloudKit to propagate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // NOW reload all data from Core Data
        // Reload task time windows
        await MainActor.run {
            TaskTimeWindowManager.shared.loadTimeWindows()
        }

        // Reload calendar events based on current interval
        switch navigationManager.currentInterval {
        case .day:
            await calendarVM.loadCalendarData(for: currentDate)
        case .week:
            await calendarVM.loadCalendarDataForWeek(containing: currentDate)
        case .month:
            await calendarVM.loadCalendarDataForMonth(containing: currentDate)
        case .year:
            // For year view, load month data for the specific month
            await calendarVM.loadCalendarDataForMonth(containing: currentDate)
        }

        // Reload tasks with forced cache clear
        await tasksVM.loadTasks(forceClear: true)

        // Reload logs data
        LogsViewModel.shared.reloadData()

        // Refresh view context
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }

        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)

        // Update last sync time
        iCloudManager.shared.lastSyncDate = Date()

        // Stop sync indicator
        await MainActor.run {
            isSyncing = false
        }
    }

    private func reloadAllDataForDate(_ date: Date) async {
        // FIRST: Force iCloud/CloudKit sync to push/pull changes
        iCloudManager.shared.forceCompleteSync()

        // Wait for CloudKit to sync
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.goalsManager.refreshData()

        // Reload custom logs data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.customLogManager.refreshData()

        // Wait for CloudKit to propagate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // NOW reload all data from Core Data
        // Reload task time windows
        await MainActor.run {
            TaskTimeWindowManager.shared.loadTimeWindows()
        }

        // Reload calendar events based on current interval
        switch navigationManager.currentInterval {
        case .day:
            await calendarVM.loadCalendarData(for: date)
        case .week:
            await calendarVM.loadCalendarDataForWeek(containing: date)
        case .month:
            await calendarVM.loadCalendarDataForMonth(containing: date)
        case .year:
            // For year view, load month data for the specific month
            await calendarVM.loadCalendarDataForMonth(containing: date)
        }
        
        // Reload tasks with forced cache clear
        await tasksVM.loadTasks(forceClear: true)
        
        // Reload logs data
        LogsViewModel.shared.reloadData()
        
        // Refresh view context
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }
        
        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
        
        // Update last sync time
        iCloudManager.shared.lastSyncDate = Date()
    }
    
}


#Preview {
    GlobalNavBar()
}
