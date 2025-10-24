import SwiftUI
import UIKit

/// High-performance image cache with memory management
@MainActor
class ImageCache: ObservableObject {
    static let shared = ImageCache()
    
    private var cache: [String: UIImage] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let maxCacheSize: Int = 50 // Maximum number of images in cache
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    
    private init() {
        // Setup memory warning observer
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Get cached image or load from URL
    func image(for url: String) -> UIImage? {
        // Check if image is in cache and not expired
        if let cachedImage = cache[url],
           let timestamp = cacheTimestamps[url],
           Date().timeIntervalSince(timestamp) < cacheTimeout {
            return cachedImage
        }
        
        // Remove expired or old entries
        cleanupCache()
        
        return nil
    }
    
    /// Cache an image with automatic memory management
    func cacheImage(_ image: UIImage, for url: String) {
        // Remove oldest entries if cache is full
        if cache.count >= maxCacheSize {
            removeOldestEntries()
        }
        
        cache[url] = image
        cacheTimestamps[url] = Date()
    }
    
    /// Remove oldest cache entries to make room
    private func removeOldestEntries() {
        let sortedEntries = cacheTimestamps.sorted { $0.value < $1.value }
        let entriesToRemove = min(10, sortedEntries.count / 2) // Remove half or 10, whichever is smaller
        
        for (key, _) in sortedEntries.prefix(entriesToRemove) {
            cache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
    }
    
    /// Clean up expired entries
    private func cleanupCache() {
        let now = Date()
        let expiredKeys = cacheTimestamps.compactMap { (key, timestamp) in
            now.timeIntervalSince(timestamp) > cacheTimeout ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
    }
    
    /// Clear all cache entries
    func clearCache() {
        cache.removeAll()
        cacheTimestamps.removeAll()
    }
    
    /// Get current cache size
    var cacheSize: Int {
        return cache.count
    }
    
    /// Get memory usage estimate
    var estimatedMemoryUsage: Int {
        return cache.values.reduce(0) { total, image in
            total + (image.cgImage?.width ?? 0) * (image.cgImage?.height ?? 0) * 4 // Rough estimate
        }
    }
}

/// Memory-efficient image view with caching
struct CachedImageView: View {
    let url: String
    let placeholder: Image
    @StateObject private var imageCache = ImageCache.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(url: String, placeholder: Image = Image(systemName: "photo")) {
        self.url = url
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // Check cache first
        if let cachedImage = imageCache.image(for: url) {
            image = cachedImage
            return
        }
        
        // Load from URL asynchronously
        isLoading = true
        Task {
            do {
                guard let imageURL = URL(string: url) else { return }
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                
                if let loadedImage = UIImage(data: data) {
                    await MainActor.run {
                        image = loadedImage
                        imageCache.cacheImage(loadedImage, for: url)
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}
