import Photos
import SwiftUI
import UIKit

@MainActor
enum PrintDayHelper {
    static let weekHorizontalScrollID = "lotus.week.export.horizontal"
    static let weekVerticalScrollID = "lotus.week.export.vertical"

    /// Snapshots the current visible window (including the nav bar) and writes it to the Photos library.
    static func saveCurrentWindowToPhotos(jobName: String) {
        guard let window = keyWindow(), let image = snapshotWindow(window) else { return }
        saveToPhotos(image, jobName: jobName)
    }

    /// Expands overflowing week scroll views (horizontal and/or vertical) so the saved
    /// image includes the summary (if any) and every day, not just the on-screen viewport.
    static func saveExpandedWindowToPhotos(jobName: String) {
        guard let window = keyWindow() else { return }

        let taggedH = findScrollView(in: window, accessibilityID: weekHorizontalScrollID)
        let taggedV = findScrollView(in: window, accessibilityID: weekVerticalScrollID)
        let horizontal = taggedH ?? findPreferredScrollView(in: window, axis: .horizontal)
        let vertical = taggedV ?? findPreferredScrollView(in: window, axis: .vertical)

        let image: UIImage?
        if let horizontal, let vertical, vertical.isDescendant(of: horizontal) {
            image = stitchColumnBasedWeek(window: window, outerHorizontal: horizontal, innerVertical: vertical)
        } else if let vertical, let horizontal, horizontal.isDescendant(of: vertical) {
            image = stitchRowBasedWeek(window: window, outerVertical: vertical, innerHorizontal: horizontal)
        } else if let vertical {
            image = stitchVerticalAndComposite(window: window, innerVertical: vertical)
        } else if let horizontal {
            image = stitchHorizontalAndComposite(window: window, innerHorizontal: horizontal)
        } else {
            image = snapshotWindow(window)
        }

        guard let image else { return }
        saveToPhotos(image, jobName: jobName)
    }

    // MARK: - Scroll view discovery

    private enum ScrollAxis {
        case horizontal
        case vertical
    }

    private static func findScrollView(in root: UIView, accessibilityID: String) -> UIScrollView? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? UIScrollView,
               scrollView.accessibilityIdentifier == accessibilityID {
                return scrollView
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private static func findPreferredScrollView(in root: UIView, axis: ScrollAxis) -> UIScrollView? {
        guard let window = root.window ?? keyWindow() else { return nil }
        var best: UIScrollView?
        var bestScore: CGFloat = 0
        var queue: [UIView] = [root]

        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? UIScrollView,
               !isLikelyChromeScrollView(scrollView, window: window) {
                let overflow: CGFloat
                let contentExtent: CGFloat
                switch axis {
                case .horizontal:
                    overflow = scrollView.contentSize.width - scrollView.bounds.width
                    contentExtent = scrollView.contentSize.width
                case .vertical:
                    overflow = scrollView.contentSize.height - scrollView.bounds.height
                    contentExtent = scrollView.contentSize.height
                }
                if overflow > 0.5, contentExtent > bestScore {
                    best = scrollView
                    bestScore = contentExtent
                }
            }
            queue.append(contentsOf: view.subviews)
        }
        return best
    }

    /// Nav-bar and other chrome scrollers are short and sit near the top; never treat them
    /// as the week content we should expand for Photos export.
    private static func isLikelyChromeScrollView(_ scrollView: UIScrollView, window: UIWindow) -> Bool {
        let frame = scrollView.convert(scrollView.bounds, to: window)
        if frame.height <= 56 { return true }
        if frame.maxY <= 180, frame.height < 120 { return true }
        return false
    }

    private static func primaryContentSubview(of scrollView: UIScrollView) -> UIView? {
        let target = scrollView.contentSize
        var best: UIView?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        for sub in scrollView.subviews {
            let name = String(describing: type(of: sub))
            if name.contains("Scroll") || name.contains("Indicator") { continue }
            let score = abs(sub.bounds.width - target.width) + abs(sub.bounds.height - target.height)
            if score < bestScore {
                best = sub
                bestScore = score
            }
        }
        return best
    }

    // MARK: - Stitching

    private struct ScrollChrome {
        let offset: CGPoint
        let showsVertical: Bool
        let showsHorizontal: Bool
        let bounces: Bool
        let alwaysBounceVertical: Bool
        let alwaysBounceHorizontal: Bool
        let hiddenIndicators: [(view: UIView, wasHidden: Bool)]
    }

    private static func prepareForSnapshot(_ scrollView: UIScrollView) -> ScrollChrome {
        var hiddenIndicators: [(view: UIView, wasHidden: Bool)] = []
        for subview in scrollView.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("ScrollIndicator") || name.contains("Scroller") {
                hiddenIndicators.append((subview, subview.isHidden))
                subview.isHidden = true
            }
        }
        let chrome = ScrollChrome(
            offset: scrollView.contentOffset,
            showsVertical: scrollView.showsVerticalScrollIndicator,
            showsHorizontal: scrollView.showsHorizontalScrollIndicator,
            bounces: scrollView.bounces,
            alwaysBounceVertical: scrollView.alwaysBounceVertical,
            alwaysBounceHorizontal: scrollView.alwaysBounceHorizontal,
            hiddenIndicators: hiddenIndicators
        )
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.setContentOffset(.zero, animated: false)
        return chrome
    }

    private static func restore(_ scrollView: UIScrollView, chrome: ScrollChrome) {
        scrollView.setContentOffset(chrome.offset, animated: false)
        scrollView.showsVerticalScrollIndicator = chrome.showsVertical
        scrollView.showsHorizontalScrollIndicator = chrome.showsHorizontal
        scrollView.bounces = chrome.bounces
        scrollView.alwaysBounceVertical = chrome.alwaysBounceVertical
        scrollView.alwaysBounceHorizontal = chrome.alwaysBounceHorizontal
        for (view, wasHidden) in chrome.hiddenIndicators {
            view.isHidden = wasHidden
        }
    }

    private static func renderView(_ view: UIView) -> UIImage? {
        let size = view.bounds.size
        guard size.width > 0.5, size.height > 0.5 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    /// Column-based week: horizontal outer (summary + all days), vertical inner (full day height).
    private static func stitchColumnBasedWeek(
        window: UIWindow,
        outerHorizontal: UIScrollView,
        innerVertical: UIScrollView
    ) -> UIImage? {
        let hChrome = prepareForSnapshot(outerHorizontal)
        let vChrome = prepareForSnapshot(innerVertical)
        outerHorizontal.layoutIfNeeded()
        innerVertical.layoutIfNeeded()
        CATransaction.flush()

        defer {
            restore(innerVertical, chrome: vChrome)
            restore(outerHorizontal, chrome: hChrome)
            innerVertical.layoutIfNeeded()
            outerHorizontal.layoutIfNeeded()
        }

        guard let baseline = snapshotWindow(window) else { return nil }

        let hFrame = outerHorizontal.convert(outerHorizontal.bounds, to: window)
        let aboveH = max(0, hFrame.origin.y)
        let belowH = max(0, window.bounds.height - hFrame.maxY)

        let hContent = primaryContentSubview(of: outerHorizontal)
        let headerH: CGFloat
        let contentOriginX: CGFloat
        if let hContent {
            let originInContent = innerVertical.convert(CGPoint.zero, to: hContent)
            headerH = max(0, originInContent.y)
            // Include any leading padding inside the horizontal content before the day grid.
            contentOriginX = hFrame.origin.x + hContent.frame.origin.x + originInContent.x
        } else {
            headerH = max(0, innerVertical.convert(CGPoint.zero, to: outerHorizontal).y)
            contentOriginX = hFrame.origin.x + outerHorizontal.adjustedContentInset.left
        }

        let contentW = max(outerHorizontal.contentSize.width, innerVertical.contentSize.width)
        let dayGridW = max(innerVertical.contentSize.width, innerVertical.bounds.width)
        let contentH = innerVertical.contentSize.height
        let trailing = max(0, window.bounds.width - hFrame.maxX)
        let finalWidth = max(
            window.bounds.width,
            contentOriginX + dayGridW + trailing,
            hFrame.origin.x + contentW + trailing
        )
        let finalHeight = aboveH + headerH + contentH + belowH
        let finalSize = CGSize(width: finalWidth, height: finalHeight)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        return renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            drawTopChrome(baseline: baseline, height: aboveH, finalWidth: finalWidth)

            if headerH > 0.5, let hContent, let headerImage = renderView(hContent) {
                let scale = headerImage.scale
                let cropWidth = min(hContent.bounds.width, contentW) * scale
                let cropHeight = min(headerH, hContent.bounds.height) * scale
                let crop = CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight)
                if let cg = headerImage.cgImage?.cropping(to: crop) {
                    let drawX = hFrame.origin.x + hContent.frame.origin.x
                    UIImage(cgImage: cg, scale: scale, orientation: .up)
                        .draw(in: CGRect(x: drawX, y: aboveH, width: cropWidth / scale, height: headerH))
                }
            }

            if let vContent = primaryContentSubview(of: innerVertical),
               let contentImage = renderView(vContent) {
                contentImage.draw(in: CGRect(
                    x: contentOriginX,
                    y: aboveH + headerH,
                    width: max(vContent.bounds.width, dayGridW),
                    height: contentH
                ))
            }

            drawBottomChrome(
                baseline: baseline,
                window: window,
                belowOriginY: hFrame.maxY,
                belowH: belowH,
                drawY: aboveH + headerH + contentH,
                finalWidth: finalWidth
            )
        }
    }

    /// Row-based week: vertical outer (summary + all day rows), horizontal inner (full row width).
    private static func stitchRowBasedWeek(
        window: UIWindow,
        outerVertical: UIScrollView,
        innerHorizontal: UIScrollView
    ) -> UIImage? {
        let vChrome = prepareForSnapshot(outerVertical)
        let hChrome = prepareForSnapshot(innerHorizontal)
        outerVertical.layoutIfNeeded()
        innerHorizontal.layoutIfNeeded()
        CATransaction.flush()

        defer {
            restore(innerHorizontal, chrome: hChrome)
            restore(outerVertical, chrome: vChrome)
            innerHorizontal.layoutIfNeeded()
            outerVertical.layoutIfNeeded()
        }

        guard let baseline = snapshotWindow(window) else { return nil }
        guard let vContent = primaryContentSubview(of: outerVertical) else {
            return stitchVerticalAndComposite(window: window, innerVertical: outerVertical)
        }

        let vFrame = outerVertical.convert(outerVertical.bounds, to: window)
        let aboveH = max(0, vFrame.origin.y)
        let belowH = max(0, window.bounds.height - vFrame.maxY)
        let contentH = outerVertical.contentSize.height
        let originX = vFrame.origin.x

        // Sticky date column sits to the left of the inner horizontal scroller.
        let hOriginInContent = innerHorizontal.convert(CGPoint.zero, to: vContent)
        let stickyWidth = max(0, hOriginInContent.x)
        let hContentW = innerHorizontal.contentSize.width
        let finalWidth = max(window.bounds.width, originX + stickyWidth + hContentW + 24)
        let finalHeight = aboveH + contentH + belowH
        let finalSize = CGSize(width: finalWidth, height: finalHeight)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        return renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            drawTopChrome(baseline: baseline, height: aboveH, finalWidth: finalWidth)

            // Full outer content (sticky dates + currently visible horizontal slice).
            if let fullVertical = renderView(vContent) {
                fullVertical.draw(in: CGRect(
                    x: originX,
                    y: aboveH,
                    width: vContent.bounds.width,
                    height: contentH
                ))
            }

            // Replace the clipped horizontal region with the full-width inner content.
            if let hContent = primaryContentSubview(of: innerHorizontal),
               let horizontalImage = renderView(hContent) {
                horizontalImage.draw(in: CGRect(
                    x: originX + stickyWidth,
                    y: aboveH + hOriginInContent.y,
                    width: max(hContent.bounds.width, hContentW),
                    height: hContent.bounds.height
                ))
            }

            drawBottomChrome(
                baseline: baseline,
                window: window,
                belowOriginY: vFrame.maxY,
                belowH: belowH,
                drawY: aboveH + contentH,
                finalWidth: finalWidth
            )
        }
    }

    private static func stitchVerticalAndComposite(window: UIWindow, innerVertical: UIScrollView) -> UIImage? {
        let chrome = prepareForSnapshot(innerVertical)
        innerVertical.layoutIfNeeded()
        CATransaction.flush()

        defer {
            restore(innerVertical, chrome: chrome)
            innerVertical.layoutIfNeeded()
        }

        guard let baseline = snapshotWindow(window) else { return nil }

        let innerFrame = innerVertical.convert(innerVertical.bounds, to: window)
        let aboveH = max(0, innerFrame.origin.y)
        let belowH = max(0, window.bounds.height - innerFrame.maxY)
        let contentH = innerVertical.contentSize.height
        let finalSize = CGSize(width: window.bounds.width, height: aboveH + contentH + belowH)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        return renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            drawTopChrome(baseline: baseline, height: aboveH, finalWidth: finalSize.width)

            if let contentView = primaryContentSubview(of: innerVertical),
               let contentImage = renderView(contentView) {
                contentImage.draw(in: CGRect(
                    x: innerFrame.origin.x,
                    y: aboveH,
                    width: max(contentView.bounds.width, innerFrame.width),
                    height: contentH
                ))
            } else if let cg = baseline.cgImage?.cropping(to: CGRect(
                x: innerFrame.origin.x * baseline.scale,
                y: innerFrame.origin.y * baseline.scale,
                width: innerFrame.width * baseline.scale,
                height: innerFrame.height * baseline.scale
            )) {
                UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
                    .draw(in: CGRect(
                        x: innerFrame.origin.x,
                        y: aboveH,
                        width: innerFrame.width,
                        height: innerFrame.height
                    ))
            }

            drawBottomChrome(
                baseline: baseline,
                window: window,
                belowOriginY: innerFrame.maxY,
                belowH: belowH,
                drawY: aboveH + contentH,
                finalWidth: finalSize.width
            )
        }
    }

    private static func stitchHorizontalAndComposite(window: UIWindow, innerHorizontal: UIScrollView) -> UIImage? {
        let chrome = prepareForSnapshot(innerHorizontal)
        innerHorizontal.layoutIfNeeded()
        CATransaction.flush()

        defer {
            restore(innerHorizontal, chrome: chrome)
            innerHorizontal.layoutIfNeeded()
        }

        guard let baseline = snapshotWindow(window) else { return nil }

        let innerFrame = innerHorizontal.convert(innerHorizontal.bounds, to: window)
        let aboveH = max(0, innerFrame.origin.y)
        let belowH = max(0, window.bounds.height - innerFrame.maxY)
        let leadingX = innerFrame.origin.x + innerHorizontal.adjustedContentInset.left
        let contentW = innerHorizontal.contentSize.width
        let trailing = max(0, window.bounds.width - innerFrame.maxX)
        let finalWidth = max(window.bounds.width, leadingX + contentW + trailing)
        let finalHeight = window.bounds.height
        let finalSize = CGSize(width: finalWidth, height: finalHeight)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        return renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            drawTopChrome(baseline: baseline, height: aboveH, finalWidth: finalWidth)

            if let contentView = primaryContentSubview(of: innerHorizontal),
               let contentImage = renderView(contentView) {
                contentImage.draw(in: CGRect(
                    x: leadingX,
                    y: aboveH,
                    width: contentW,
                    height: max(contentView.bounds.height, innerFrame.height)
                ))
            }

            drawBottomChrome(
                baseline: baseline,
                window: window,
                belowOriginY: innerFrame.maxY,
                belowH: belowH,
                drawY: finalHeight - belowH,
                finalWidth: finalWidth
            )
        }
    }

    private static func drawTopChrome(baseline: UIImage, height: CGFloat, finalWidth: CGFloat) {
        guard height > 0.5,
              let cg = baseline.cgImage?.cropping(to: CGRect(
                x: 0,
                y: 0,
                width: baseline.size.width * baseline.scale,
                height: height * baseline.scale
              )) else { return }
        UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
            .draw(in: CGRect(x: 0, y: 0, width: min(baseline.size.width, finalWidth), height: height))
    }

    private static func drawBottomChrome(
        baseline: UIImage,
        window: UIWindow,
        belowOriginY: CGFloat,
        belowH: CGFloat,
        drawY: CGFloat,
        finalWidth: CGFloat
    ) {
        guard belowH > 0.5,
              let cg = baseline.cgImage?.cropping(to: CGRect(
                x: 0,
                y: belowOriginY * baseline.scale,
                width: baseline.size.width * baseline.scale,
                height: belowH * baseline.scale
              )) else { return }
        UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
            .draw(in: CGRect(
                x: 0,
                y: drawY,
                width: min(baseline.size.width, finalWidth),
                height: belowH
            ))
        _ = window
    }

    // MARK: - Window / Photos

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
        let title = success ? "Saved to Photos" : "Couldn't Save"
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

/// Attaches an accessibility identifier to the nearest enclosing `UIScrollView`
/// so Photos export can target the week content scrollers reliably.
struct WeekExportScrollTagger: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = Self.findNearbyScrollView(from: uiView) {
                scrollView.accessibilityIdentifier = identifier
            }
        }
    }

    /// SwiftUI may place this representable as a sibling of the `UIScrollView`
    /// (background/overlay), not as a descendant — search both directions.
    private static func findNearbyScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let node = current {
            if let scrollView = node as? UIScrollView {
                return scrollView
            }
            if let scrollView = node.subviews.compactMap({ $0 as? UIScrollView }).first {
                return scrollView
            }
            for sibling in node.superview?.subviews ?? [] where sibling !== node {
                if let scrollView = sibling as? UIScrollView {
                    return scrollView
                }
                if let scrollView = sibling.subviews.compactMap({ $0 as? UIScrollView }).first {
                    return scrollView
                }
            }
            current = node.superview
        }
        return nil
    }
}
