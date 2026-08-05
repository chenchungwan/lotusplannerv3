import Photos
import SwiftUI
import UIKit

@MainActor
enum PrintDayHelper {
    /// Snapshots the current visible window (including the nav bar) and writes it to the Photos library.
    static func saveCurrentWindowToPhotos(jobName: String) {
        guard let window = keyWindow(), let image = snapshotWindow(window) else { return }
        saveToPhotos(image, jobName: jobName)
    }

    /// Like `saveCurrentWindowToPhotos`, but expands the largest overflowing vertical scroll view.
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
        let finalSize = CGSize(width: window.bounds.width, height: aboveH + contentH + belowH)

        let renderer = UIGraphicsImageRenderer(size: finalSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: finalSize))

            if aboveH > 0,
               let cg = baseline.cgImage?.cropping(to: CGRect(
                x: 0,
                y: 0,
                width: baseline.size.width * baseline.scale,
                height: aboveH * baseline.scale
               )) {
                UIImage(cgImage: cg, scale: baseline.scale, orientation: .up)
                    .draw(in: CGRect(x: 0, y: 0, width: baseline.size.width, height: aboveH))
            }

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
            }

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
