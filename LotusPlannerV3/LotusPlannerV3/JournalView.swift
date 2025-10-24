import SwiftUI
import PDFKit
import PencilKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

enum SaveStatus: Equatable {
    case idle
    case saving
    case saved
    case error(String)
}

struct JournalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var drawingManager = JournalDrawingManagerNew.shared
    @Binding var currentDate: Date
    @State private var canvasView = PKCanvasView()
    // Track previous date to save when date changes
    @State private var previousDate: Date
    /// Current canvas size used to normalize photo placement across layouts
    @State private var canvasSize: CGSize = .zero
    /// Whether the PKToolPicker is currently visible.
    @State private var showToolPicker: Bool = false
    /// Selected items from Photos picker (temporary).
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Photos placed on the canvas.
    @State private var photos: [JournalPhoto] = []
    /// Show confirmation alert before erasing journal content
    @State private var showingEraseConfirmation = false
    /// Loading states for sync status indicators
    @State private var isLoadingDrawings = false
    @State private var isLoadingPhotos = false
    /// Prevents concurrent save/load operations
    @State private var isSavingOrLoading = false
    /// Tracks the currently loaded date to prevent stale data
    @State private var loadedDate: Date?
    /// Save status for UI feedback
    @State private var saveStatus: SaveStatus = .idle
    /// Retry download state
    @State private var showRetryDownload = false
    /// Prevents duplicate photo processing
    @State private var isProcessingPhotos = false

    /// When `embedded` is `true` the view shows only the canvas/background
    /// content and omits its own `NavigationStack` + toolbars so it can be
    /// embedded inside another navigation hierarchy without duplicating the
    /// nav bar.
    var embedded: Bool = false
    
    /// Layout type for determining which background PDF to use
    var layoutType: JournalLayoutType = .compact
    
    init(currentDate: Binding<Date>, embedded: Bool = false, layoutType: JournalLayoutType = .compact) {
        _currentDate = currentDate
        _previousDate = State(initialValue: currentDate.wrappedValue)
        self.embedded = embedded
        self.layoutType = layoutType
    }
    
    // Interval is always day for journal navigation (reuse same step logic)
    private func step(_ direction: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: direction, to: currentDate) else { return }
        // Let the date change handler handle saving
        previousDate = currentDate
        currentDate = newDate
    }

    private func loadDrawing() {
        // Load asynchronously to support iCloud evict/download
        Task { @MainActor in
            await loadDrawingAsync()
        }
    }
    
    private func loadDrawingAsync() async {
        guard !isSavingOrLoading else {
            print("⚠️ JournalView: Skipping drawing load - save/load in progress")
            return
        }
        
        isLoadingDrawings = true
        print("🔄 JournalView: Loading drawing for journal page date: \(currentDate)")
        
        // Ensure we're loading for the correct date
        let targetDate = currentDate
        if let drawing = await JournalStorageNew.shared.load(for: targetDate) {
            // Double-check we're still on the same date
            if targetDate == currentDate {
                canvasView.drawing = drawing
                loadedDate = targetDate
                print("🔄 JournalView: Loaded existing drawing for date: \(targetDate)")
            } else {
                print("⚠️ JournalView: Date changed during drawing load, ignoring stale data")
            }
        } else {
            if targetDate == currentDate {
                canvasView.drawing = PKDrawing()
                loadedDate = targetDate
                print("🔄 JournalView: No existing drawing found for date: \(targetDate)")
            }
        }
        isLoadingDrawings = false
    }
    
    /// Explicit save to iCloud - saves both drawing and photos
    private func saveToiCloud() async {
        guard !isSavingOrLoading else {
            print("⚠️ JournalView: Save blocked - operation in progress")
            return
        }
        
        isSavingOrLoading = true
        saveStatus = .saving
        
        print("💾 JournalView: Starting explicit save to iCloud for \(currentDate)")
        
        do {
            // Save drawing
            print("💾 JournalView: Saving drawing to iCloud")
            try await JournalStorageNew.shared.save(canvasView.drawing, for: currentDate)
            
            // Save photos
            print("💾 JournalView: Saving photos to iCloud")
            savePhotos(for: currentDate)
            
            saveStatus = .saved
            print("✅ JournalView: Successfully saved to iCloud")
            
            // Clear save status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if case .saved = saveStatus {
                    saveStatus = .idle
                }
            }
            
        } catch {
            saveStatus = .error(error.localizedDescription)
            print("❌ JournalView: Failed to save to iCloud: \(error.localizedDescription)")
        }
        
        isSavingOrLoading = false
    }
    
    /// Load from iCloud with retry mechanism
    private func loadFromiCloud() async {
        guard !isSavingOrLoading else {
            print("⚠️ JournalView: Load blocked - operation in progress")
            return
        }
        
        isSavingOrLoading = true
        showRetryDownload = false
        
        print("📥 JournalView: Loading from iCloud for \(currentDate)")
        
        do {
            // Load drawing
            if let drawing = await JournalStorageNew.shared.load(for: currentDate) {
                canvasView.drawing = drawing
                print("📥 JournalView: Successfully loaded drawing from iCloud")
            } else {
                canvasView.drawing = PKDrawing()
                print("📥 JournalView: No drawing found in iCloud")
            }
            
            // Load photos
            await loadPhotos(for: currentDate)
            
            loadedDate = currentDate
            print("✅ JournalView: Successfully loaded from iCloud")
            
        } catch {
            print("❌ JournalView: Failed to load from iCloud: \(error.localizedDescription)")
            showRetryDownload = true
        }
        
        isSavingOrLoading = false
    }
    
    /// Simple date switching - only loads new content, no automatic saving
    private func switchToDate(_ newDate: Date) async {
        guard !isSavingOrLoading else {
            print("⚠️ JournalView: Date switch blocked - save/load in progress")
            return
        }
        
        isSavingOrLoading = true
        
        print("🔄 JournalView: Switching to date \(newDate)")
        
        // Clear UI state
        photos.removeAll()
        canvasView.drawing = PKDrawing()
        
        // Load new content from iCloud
        await loadFromiCloud()
        
        isSavingOrLoading = false
    }
    
    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: currentDate)
    }
    
    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 8) {
                    topToolbar
                    canvasContent
                        .padding(.bottom, 12)
                }
                    .onAppear {
                        // Load content from iCloud
                        Task { @MainActor in
                            await loadFromiCloud()
                        }
                    }
                    .onDisappear {
                        // No automatic saving - user must explicitly save
                    }
        .onChange(of: currentDate) { oldValue, newValue in
            print("🔄 JournalView (embedded): Date changed from \(oldValue) to \(newValue)")
            Task { @MainActor in
                await switchToDate(newValue)
            }
        }
        .onChange(of: pickerItems) { oldValue, newValue in
            print("📸 Photo picker selection changed: \(oldValue.count) -> \(newValue.count) items")
            if !newValue.isEmpty {
                print("📸 Photo picker has \(newValue.count) new items, calling loadSelectedPhotos()")
                loadSelectedPhotos()
            }
        }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshJournalContent"))) { _ in
                        print("🔄 JournalView (embedded): Received RefreshJournalContent notification")
                        Task { @MainActor in
                            // Refresh journal content when notification is received
                            await switchToDate(currentDate)
                        }
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 8) {
                        topToolbar
                        canvasContent
                    }
                        .navigationTitle("")
                        .toolbarTitleDisplayMode(.inline)
                        .onAppear {
                            // Load content from iCloud
                            Task { @MainActor in
                                await loadFromiCloud()
                            }
                        }
                        .onChange(of: currentDate) { oldValue, newValue in
                            Task { @MainActor in
                                await switchToDate(newValue)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshJournalContent"))) { _ in
                            Task { @MainActor in
                                // Refresh journal content when notification is received
                                await switchToDate(currentDate)
                            }
                        }
                        .onDisappear {
                            // No automatic saving - user must explicitly save
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .navigationBarLeading) {
                                HStack(spacing: 8) {
                                    SharedNavigationToolbar()
                                    Button(action: { step(-1) }) {
                                        Image(systemName: "chevron.left")
                                    }
                                    Text(dayTitle)
                                        .font(.headline)
                                    Button(action: { step(1) }) {
                                        Image(systemName: "chevron.right")
                                    }
                                    Spacer()
                                    Button(action: { showToolPicker.toggle() }) {
                                        Image(systemName: "applepencil.and.scribble")
                                    }
                                    if #available(iOS 17, *) {
                                        PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                                            Image(systemName: "photo.badge.plus.fill")
                                        }
                                    } else {
                                        PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                                            Image(systemName: "photo.badge.plus.fill")
                                        }
                                    }
                                    Button(action: { showingEraseConfirmation = true }) {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    Task { @MainActor in
                                        // Save any pending changes
                                        await drawingManager.saveImmediately()
                                        savePhotos()
                                        dismiss()
                                    }
                                }
                            }
                        }
                }
            }
        }
        .alert("Clear Journal", isPresented: $showingEraseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearJournal()
            }
        } message: {
            Text("Are you sure you want to erase all content from today's journal? This action cannot be undone.")
        }
    }

    // MARK: - Top toolbar inline (all icons on same line as title)
    private var topToolbar: some View {
        HStack {
            Text("Journal")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 16) {
                // iCloud Save button
                Button(action: {
                    Task { @MainActor in
                        await saveToiCloud()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                        
                        switch saveStatus {
                        case .idle:
                            Text("Save")
                                .font(.system(size: 14, weight: .medium))
                        case .saving:
                            Text("Saving...")
                                .font(.system(size: 14, weight: .medium))
                        case .saved:
                            Text("Saved")
                                .font(.system(size: 14, weight: .medium))
                        case .error:
                            Text("Error")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor({
                        switch saveStatus {
                        case .error:
                            return .red
                        case .saved:
                            return .green
                        default:
                            return .primary
                        }
                    }())
                }
                .disabled(isSavingOrLoading)
                
                Button(action: { showToolPicker.toggle() }) {
                    Image(systemName: "applepencil.and.scribble")
                }
                if #available(iOS 17, *) {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo.badge.plus.fill")
                    }
                } else {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo.badge.plus.fill")
                    }
                }
                Button(action: { showingEraseConfirmation = true }) {
                    Image(systemName: "trash")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var canvasContent: some View {
        GeometryReader { geo in
            let newSize = geo.size
            ZStack {
            // Observe photo picker selection
        
            // Clean white background
            Group {
                Color.white
            }
            .ignoresSafeArea(embedded ? [] : .all)

            // PencilKit canvas overlay
            Group {
                PencilKitView(
                    canvasView: $canvasView,
                    showsToolPicker: showToolPicker,
                    onDrawingChanged: {
                        // No automatic saving - user must explicitly save
                        print("🔄 JournalView: Drawing changed for date: \(currentDate)")
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        .padding(1)
                )
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        if drawingManager.isSaving {
                            ProgressView()
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                        if isLoadingDrawings {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading drawings...")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                        if isLoadingPhotos {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading photos...")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .ignoresSafeArea(embedded ? [] : .all)
            // Movable photos overlay
            ForEach(photos.indices, id: \.self) { idx in
                DraggablePhotoView(
                    photo: $photos[idx],
                    onDelete: {
                        photos.remove(at: idx)
                    },
                    onChanged: {
                        // Persist edits so divider/layout changes don't undo user changes
                        savePhotos()
                    }
                )
            }
            
            // Retry download overlay
            if showRetryDownload {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Failed to load from iCloud")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Your journal content couldn't be downloaded. This might be due to network issues or iCloud sync problems.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: {
                        Task { @MainActor in
                            await loadFromiCloud()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Download")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.95))
            }
            
            // (Floating controls removed; replaced by topToolbar)
            }
            .onAppear {
                if canvasSize != newSize {
                    canvasSize = newSize
                }
            }
            .onChange(of: newSize) { _, size in
                // Update size and reflow when layout changes
                canvasSize = size
                Task { @MainActor in
                    // Only reload photos if not in the middle of a save/load operation
                    guard !isSavingOrLoading else { return }
                    await loadPhotos()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                switch newPhase {
                case .inactive, .background:
                    // No automatic saving - user must explicitly save
                    break
                case .active:
                    // Reload content when becoming active
                    await switchToDate(currentDate)
                @unknown default:
                    break
                }
            }
        }
    }
    
    // (Old floating controlButtons removed)
    
    // MARK: - Clear Journal
    private func clearJournal() {
        // Clear drawing
        canvasView.drawing = PKDrawing()
        JournalStorageNew.shared.saveSync(canvasView.drawing, for: currentDate)
        
        // Clear photos from memory
        photos.removeAll()
        
        // Delete photo files for current date
        let metaURL = metadataURL(for: currentDate)
        if let data = try? Data(contentsOf: metaURL),
           let metas = try? JSONDecoder().decode([PhotoMeta].self, from: data) {
            // Delete each photo file
            for meta in metas {
                let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // Clear metadata file
        let empty: [PhotoMeta] = []
        if let jsonData = try? JSONEncoder().encode(empty) {
            try? jsonData.write(to: metaURL, options: .atomic)
        }
    }

    private func exportJournal() {
        // Save current drawing/photos first
        JournalStorageNew.shared.saveSync(canvasView.drawing, for: currentDate)
        savePhotos()
        // Stub: actual export (PDF/image) can be implemented as needed
    }
    
    // MARK: - Photo Data Persistence
    private struct PhotoMeta: Codable {
        let id: String
        let fileName: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let rotation: Double
        let nx: Double?
        let ny: Double?
        let nw: Double?
        let nh: Double?
        let cw: Double?
        let ch: Double?
    }
    
    /// Directory where per-day photo PNGs are stored.
    /// Uses the same directory as JournalManager for consistency
    private func photosDirectory() -> URL {
        return JournalManager.shared.photosDirectoryURL
    }
    private func metadataURL(for date: Date) -> URL {
        return JournalManager.shared.metadataURL(for: date)
    }
    
    private func savePhotos(for date: Date? = nil) {
        do {
            let targetDate = date ?? currentDate
            print("🔄 JournalView: Saving \(photos.count) photos for journal page date: \(targetDate)")
            print("🔄 JournalView: Current system date: \(Date())")
            print("🔄 JournalView: NavigationManager.currentDate: \(NavigationManager.shared.currentDate)")
            print("📸 savePhotos: Photos array details:")
            for (index, photo) in photos.enumerated() {
                print("📸 savePhotos: Photo \(index + 1): ID=\(photo.id), Size=\(photo.size), Position=\(photo.position)")
            }
            
            // Always write a metadata file (can be empty) so existence checks are consistent
            // across sessions. Remove per-photo images only when clearing all.
            if photos.isEmpty {
                print("📸 savePhotos: Photos array is empty, writing empty metadata file")
                let empty: [PhotoMeta] = []
                let jsonData = try JSONEncoder().encode(empty)
                try jsonData.write(to: metadataURL(for: targetDate), options: .atomic)
                print("📸 savePhotos: Wrote empty metadata file to: \(metadataURL(for: targetDate).path)")
                return
            }
            
            var metas: [PhotoMeta] = []
            let photoDir = photosDirectory()
            
            for photo in photos {
                let id = photo.id.uuidString
                let fileName = id + ".png"
                let fileURL = photoDir.appendingPathComponent(fileName)
                
                print("🔄 JournalView: Saving photo with ID: \(id) to date: \(targetDate)")
                
                if let data = photo.image.pngData() {
                    try data.write(to: fileURL, options: .atomic)
                }
                let cw = max(canvasSize.width, 1)
                let ch = max(canvasSize.height, 1)
                let nx = Double(photo.position.x / cw)
                let ny = Double(photo.position.y / ch)
                let nw = Double(photo.size.width / cw)
                let nh = Double(photo.size.height / ch)
                metas.append(
                    PhotoMeta(
                        id: id,
                        fileName: fileName,
                        x: photo.position.x,
                        y: photo.position.y,
                        width: photo.size.width,
                        height: photo.size.height,
                        rotation: photo.rotation.radians,
                        nx: nx,
                        ny: ny,
                        nw: nw,
                        nh: nh,
                        cw: Double(cw),
                        ch: Double(ch)
                    )
                )
            }
            
            let jsonData = try JSONEncoder().encode(metas)
            let url = metadataURL(for: targetDate)
            try jsonData.write(to: url, options: [.atomic])
            print("🔄 JournalView: Saved metadata to: \(url.path)")
            
            // Log all saved photo files
            print("📸 ==================== SAVED PHOTO FILES ====================")
            for (index, meta) in metas.enumerated() {
                let fileURL = photoDir.appendingPathComponent(meta.fileName)
                print("📸 [\(index + 1)] \(meta.fileName)")
                print("📸     ID: \(meta.id)")
                print("📸     Size: \(meta.width)x\(meta.height)")
                print("📸     Position: (\(meta.x), \(meta.y))")
                print("📸     Full Path: \(fileURL.path)")
                print("📸     ---")
            }
            print("📸 ========================================================")
        } catch {
            // Silently fail - photos will be retried on next save
        }
    }
    private func loadPhotos(for date: Date? = nil) async {
        let targetDate = date ?? currentDate
        print("🔄 JournalView: Loading photos for date: \(targetDate)")
        print("🔄 JournalView: Photos directory: \(photosDirectory().path)")
        print("🔄 JournalView: Metadata URL: \(metadataURL(for: targetDate).path)")
        
        // Log all files in iCloud photos directory
        await logiCloudPhotoFiles()
        
        photos.removeAll()
        isLoadingPhotos = true
        
        // Load photos with robust retry logic
        await loadPhotosWithRetry(for: targetDate, maxRetries: 3)
        isLoadingPhotos = false
    }
    
    /// Load photos with retry logic and robust iCloud handling
    private func loadPhotosWithRetry(for date: Date, maxRetries: Int) async {
        for attempt in 1...maxRetries {
            do {
                let url = metadataURL(for: date)
                print("🔄 JournalView: Attempt \(attempt)/\(maxRetries) - Loading photos from: \(url.path)")
                
                // Check if metadata file exists
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("⚠️ Photo metadata file does not exist: \(url.path)")
                    print("🔄 JournalView: No photos to load for \(date)")
                    return
                }
                
                // Apply same robust iCloud handling as drawings
                await ensureFileDownloadedWithRetry(url: url, maxRetries: 3)
                
                // Load metadata
                let data = try Data(contentsOf: url)
                print("📸 Photo metadata file size: \(data.count) bytes")
                print("📸 Photo metadata content: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")
                
                let metas = try JSONDecoder().decode([PhotoMeta].self, from: data)
                
                print("🔄 JournalView: Found \(metas.count) photo metadata entries")
                
                // If no photos found in iCloud, check local storage as fallback
                if metas.isEmpty {
                    print("📸 No photos in iCloud, checking local storage...")
                    let localURL = JournalManager.shared.localPhotosURL.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        print("📸 Found local metadata file, attempting to load...")
                        do {
                            let localData = try Data(contentsOf: localURL)
                            let localMetas = try JSONDecoder().decode([PhotoMeta].self, from: localData)
                            print("📸 Found \(localMetas.count) photos in local storage")
                            
                            // Copy to iCloud for future use
                            try localData.write(to: url, options: .atomic)
                            print("📸 Copied local photos to iCloud")
                            
                            // Use local photos
                            var loadedPhotos: [JournalPhoto] = []
                            for meta in localMetas {
                                if let photo = await loadPhotoWithRetry(meta: meta, maxRetries: 2) {
                                    loadedPhotos.append(photo)
                                }
                            }
                            photos = loadedPhotos
                            print("✅ Successfully loaded \(loadedPhotos.count) photos from local storage for \(date)")
                            return
                        } catch {
                            print("❌ Failed to load local photos: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Load each photo with robust handling
                var loadedPhotos: [JournalPhoto] = []
                for meta in metas {
                    if let photo = await loadPhotoWithRetry(meta: meta, maxRetries: 2) {
                        loadedPhotos.append(photo)
                    }
                }
                
                // Update photos array atomically
                photos = loadedPhotos
                print("✅ Successfully loaded \(loadedPhotos.count) photos for \(date)")
                return
                
            } catch {
                print("❌ Attempt \(attempt)/\(maxRetries) failed for photos on \(date): \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    // Exponential backoff: 1s, 2s
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        print("❌ Failed to load photos after \(maxRetries) attempts for \(date)")
    }
    
    /// Load individual photo with retry logic
    private func loadPhotoWithRetry(meta: PhotoMeta, maxRetries: Int) async -> JournalPhoto? {
        let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
        
        for attempt in 1...maxRetries {
            do {
                // Check if file exists
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("⚠️ Photo file does not exist: \(meta.fileName)")
                    return nil
                }
                
                // Ensure photo file is downloaded if in iCloud
                await ensureFileDownloaded(url: fileURL)
                
                // Load photo data
                let data = try Data(contentsOf: fileURL)
                guard let uiImg = UIImage(data: data) else {
                    print("⚠️ Failed to create UIImage from data for: \(meta.fileName)")
                    return nil
                }
                
                // Calculate position and size
                let width = canvasSize.width > 0 ? canvasSize.width : UIScreen.main.bounds.width
                let height = canvasSize.height > 0 ? canvasSize.height : UIScreen.main.bounds.height
                let posX: CGFloat
                let posY: CGFloat
                let sizeW: CGFloat
                let sizeH: CGFloat
                
                if let nx = meta.nx, let ny = meta.ny, let _ = meta.nw, let _ = meta.nh {
                    // Keep photo size constant across divider/canvas size changes
                    posX = CGFloat(nx) * width
                    posY = CGFloat(ny) * height
                    sizeW = CGFloat(meta.width)
                    sizeH = CGFloat(meta.height)
                } else {
                    posX = CGFloat(meta.x)
                    posY = CGFloat(meta.y)
                    sizeW = CGFloat(meta.width)
                    sizeH = CGFloat(meta.height)
                }
                
                // Validate dimensions to prevent "Invalid frame dimension" errors
                let validWidth = max(1.0, sizeW.isFinite ? sizeW : 120.0)
                let validHeight = max(1.0, sizeH.isFinite ? sizeH : 120.0)
                let validPosX = posX.isFinite ? posX : 150.0
                let validPosY = posY.isFinite ? posY : 150.0
                
                let photo = JournalPhoto(
                    id: UUID(uuidString: meta.id) ?? UUID(),
                    image: uiImg,
                    position: CGPoint(x: validPosX, y: validPosY),
                    size: CGSize(width: validWidth, height: validHeight),
                    rotation: Angle(radians: meta.rotation)
                )
                
                print("✅ Successfully loaded photo: \(meta.id)")
                return photo
                
            } catch {
                print("❌ Photo load attempt \(attempt)/\(maxRetries) failed for \(meta.fileName): \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    let delay = UInt64(500_000_000) // 0.5 seconds
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        print("❌ Failed to load photo after \(maxRetries) attempts: \(meta.fileName)")
        return nil
    }
    
    /// Ensure iCloud file is fully downloaded with robust retry logic
    private func ensureFileDownloadedWithRetry(url: URL, maxRetries: Int) async {
        for attempt in 1...maxRetries {
            do {
                // Check if file is in iCloud
                var isUbiquitous: AnyObject?
                try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                let isInCloud = (isUbiquitous as? Bool) == true
                
                if isInCloud {
                    print("📸 Photo metadata is in iCloud, ensuring download...")
                    
                    // Force evict stale cache and re-download fresh version
                    try? FileManager.default.evictUbiquitousItem(at: url)
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    
                    // Wait for download with timeout
                    let timeout: TimeInterval = 3.0
                    let startTime = Date()
                    
                    while Date().timeIntervalSince(startTime) < timeout {
                        var downloadStatus: AnyObject?
                        try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
                        
                        if let status = downloadStatus as? URLUbiquitousItemDownloadingStatus {
                            if status == .current {
                                print("📸 Photo metadata download completed")
                                return
                            }
                        }
                        
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                    
                    print("⚠️ Photo metadata download timeout, proceeding with available data")
                } else {
                    print("📸 Photo metadata is local, no download needed")
                }
                return
                
            } catch {
                print("❌ Photo metadata download attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    let delay = UInt64(500_000_000) // 0.5 seconds
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        print("❌ Failed to download photo metadata after \(maxRetries) attempts")
    }
    
    /// Log all files in iCloud photos directory
    private func logiCloudPhotoFiles() async {
        let photosDir = photosDirectory()
        print("📁 ==================== iCLOUD PHOTOS DIRECTORY ====================")
        print("📁 Directory: \(photosDir.path)")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: [.fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [])
            
            print("📁 Found \(contents.count) files in iCloud photos directory:")
            
            for (index, url) in contents.enumerated() {
                let fileName = url.lastPathComponent
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                
                // Check if file is in iCloud
                var isUbiquitous: AnyObject?
                try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
                let isInCloud = (isUbiquitous as? Bool) == true
                
                // Check download status
                var downloadStatus: AnyObject?
                try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
                let status = downloadStatus as? URLUbiquitousItemDownloadingStatus
                
                print("📁 [\(index + 1)] \(fileName)")
                print("📁     Size: \(fileSize) bytes")
                print("📁     In iCloud: \(isInCloud)")
                print("📁     Download Status: \(String(describing: status))")
                print("📁     Full Path: \(url.path)")
                print("📁     ---")
            }
            
            if contents.isEmpty {
                print("📁 Directory is empty")
            }
            
        } catch {
            print("📁 Error listing iCloud photos directory: \(error.localizedDescription)")
        }
        
        print("📁 ========================================================")
    }
    
    /// Ensure iCloud file is fully downloaded
    private func ensureFileDownloaded(url: URL) async {
        // Check if file is in iCloud
        var isUbiquitous: AnyObject?
        try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
        let isInCloud = (isUbiquitous as? Bool) == true
        
        if !isInCloud {
            return // Not in iCloud, no need to wait
        }
        
        // Start download if needed
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        
        // Wait for download to complete with timeout
        let maxWaitTime: UInt64 = 3_000_000_000 // 3 seconds
        let checkInterval: UInt64 = 100_000_000 // 0.1 seconds
        var totalWaitTime: UInt64 = 0
        
        while totalWaitTime < maxWaitTime {
            var downloadStatus: AnyObject?
            try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
            
            if let status = downloadStatus as? URLUbiquitousItemDownloadingStatus {
                if status == .current {
                    return // Fully downloaded
                }
            }
            
            try? await Task.sleep(nanoseconds: checkInterval)
            totalWaitTime += checkInterval
        }
        
        print("⚠️ iCloud download timeout for \(url.lastPathComponent), proceeding with available data")
    }
    private func loadSelectedPhotos() {
        guard !pickerItems.isEmpty else { 
            print("📸 loadSelectedPhotos: No picker items to process")
            return 
        }
        
        guard !isSavingOrLoading else {
            print("⚠️ loadSelectedPhotos: Blocked - save/load in progress")
            return
        }
        
        // Prevent duplicate processing
        guard !isProcessingPhotos else {
            print("⚠️ loadSelectedPhotos: Already processing photos, skipping duplicate call")
            return
        }
        
        isProcessingPhotos = true
        let targetDate = currentDate
        print("🔄 JournalView: Loading \(pickerItems.count) selected photos for journal page date: \(targetDate)")
        print("🔄 JournalView: NavigationManager.currentDate: \(NavigationManager.shared.currentDate)")
        print("📸 loadSelectedPhotos: Current photos array has \(photos.count) photos before adding new ones")
        
        Task {
            var loadedPhotos: [JournalPhoto] = []
            
            for (index, item) in pickerItems.enumerated() {
                print("📸 loadSelectedPhotos: Processing picker item \(index + 1)/\(pickerItems.count)")
                do {
                    if let data = try? await item.loadTransferable(type: Data.self), let uiImg = UIImage(data: data) {
                        let position = CGPoint(x: 150, y: 150)
                        let size = CGSize(width: 120, height: 120)
                        let newPhoto = JournalPhoto(id: UUID(), image: uiImg, position: position, size: size, rotation: .zero)
                        
                        loadedPhotos.append(newPhoto)
                        print("📸 loadSelectedPhotos: Successfully loaded photo with ID: \(newPhoto.id)")
                    } else {
                        print("❌ loadSelectedPhotos: Failed to load transferable data or create UIImage for item \(index + 1)")
                    }
                } catch {
                    print("❌ loadSelectedPhotos: Error loading transferable for item \(index + 1): \(error.localizedDescription)")
                }
            }
            
            // Update photos array on main thread and save
            await MainActor.run {
                // Double-check we're still on the same date
                guard targetDate == currentDate else {
                    print("⚠️ loadSelectedPhotos: Date changed during photo loading, ignoring")
                    isProcessingPhotos = false
                    return
                }
                
                photos.append(contentsOf: loadedPhotos)
                print("📸 loadSelectedPhotos: Added \(loadedPhotos.count) photos to array. Total photos: \(photos.count)")
                pickerItems.removeAll()
                print("📸 loadSelectedPhotos: About to save photos. Current photos array has \(photos.count) photos")
                savePhotos(for: targetDate) // Save to the journal page date, not current system date
                
                // Reset processing flag
                isProcessingPhotos = false
            }
        }
    }
    
    
    
    // MARK: - Photo model & view
    struct JournalPhoto: Identifiable {
        let id: UUID
        var image: UIImage
        var position: CGPoint
        var size: CGSize
        var rotation: Angle
    }
    
    
    struct DraggablePhotoView: View {
        @Binding var photo: JournalPhoto
        var onDelete: () -> Void
        var onChanged: () -> Void = {}

        @State private var dragOffset: CGSize = .zero
        @State private var scale: CGFloat = 1.0
        @State private var rotationAngle: Angle = .zero
        @State private var showDelete: Bool = false

        var body: some View {
            ZStack(alignment: .topLeading) {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: max(1.0, photo.size.width * scale),
                        height: max(1.0, photo.size.height * scale)
                    )
                    .rotationEffect(photo.rotation + rotationAngle)

                if showDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .offset(x: -10, y: -10) // slight offset outward
                }
            }
            .position(
                x: max(0, photo.position.x + dragOffset.width),
                y: max(0, photo.position.y + dragOffset.height)
            )
            .gesture(dragGesture.simultaneously(with: magnificationGesture).simultaneously(with: rotationGesture))
            .onTapGesture {
                withAnimation { showDelete.toggle() }
            }
            .onChange(of: photo.position) { _ in
                // Persist after moves
                DispatchQueue.main.async {
                    // parent will handle save via binding context
                }
            }
        }
        // Drag
        private var dragGesture: some Gesture {
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    photo.position.x += value.translation.width
                    photo.position.y += value.translation.height
                    dragOffset = .zero
                    onChanged()
                }
        }
        // Resize
        private var magnificationGesture: some Gesture {
            MagnificationGesture()
                .onChanged { scaleVal in
                    scale = scaleVal
                }
                .onEnded { scaleVal in
                    photo.size.width *= scaleVal
                    photo.size.height *= scaleVal
                    scale = 1.0
                    onChanged()
                }
        }
        // Rotate
        private var rotationGesture: some Gesture {
            RotationGesture()
                .onChanged { angle in
                    rotationAngle = angle
                }
                .onEnded { angle in
                    photo.rotation += angle
                    rotationAngle = .zero
                    onChanged()
                }
        }
    }
    
}



#Preview {
    JournalView(currentDate: .constant(Date()))
} 
