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
    /// The date that the current content actually belongs to (not the view date)
    @State private var contentDate: Date?
    /// Save status for UI feedback
    @State private var saveStatus: SaveStatus = .idle
    /// Retry download state
    @State private var showRetryDownload = false
    /// Prevents duplicate photo processing
    @State private var isProcessingPhotos = false
    /// Shows unsaved changes warning
    @State private var showUnsavedChangesAlert = false

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
        logPerformance("Loading drawing for journal page date: \(currentDate)")
        
        // Ensure we're loading for the correct date
        let targetDate = currentDate
        if let drawing = await JournalStorageNew.shared.load(for: targetDate) {
            // Double-check we're still on the same date
            if targetDate == currentDate {
                canvasView.drawing = drawing
                loadedDate = targetDate
                logPerformance("Loaded existing drawing for date: \(targetDate)")
            } else {
                logWarning("Date changed during drawing load, ignoring stale data")
            }
        } else {
            if targetDate == currentDate {
                canvasView.drawing = PKDrawing()
                loadedDate = targetDate
                logPerformance("No existing drawing found for date: \(targetDate)")
            }
        }
        isLoadingDrawings = false
    }
    
    /// Explicit save to iCloud - saves both drawing and photos
    private func saveToiCloud() async {
        guard !isSavingOrLoading else {
            return
        }
        
        isSavingOrLoading = true
        saveStatus = .saving
        
        do {
            // Use contentDate if available, otherwise fall back to currentDate
            let saveDate = contentDate ?? currentDate
            
            // Save drawing
            try await JournalStorageNew.shared.save(canvasView.drawing, for: saveDate)
            
            // Save photos
            savePhotos(for: saveDate)
            
            saveStatus = .saved
            
            // Print detailed save information
            print("💾 JOURNAL EXIT - Saving content for date: \(formatDateForDisplay(saveDate))")
            print("💾 JOURNAL EXIT - Drawing strokes: \(canvasView.drawing.strokes.count)")
            print("💾 JOURNAL EXIT - Photos count: \(photos.count)")
            if !photos.isEmpty {
                for (index, photo) in photos.enumerated() {
                    print("💾 JOURNAL EXIT - Photo \(index + 1): \(photo.id) (\(Int(photo.size.width))x\(Int(photo.size.height)))")
                }
            }
            
            // Clear save status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if case .saved = saveStatus {
                    saveStatus = .idle
                }
            }
            
        } catch {
            saveStatus = .error(error.localizedDescription)
            print("❌ JOURNAL EXIT - Save failed: \(error.localizedDescription)")
        }
        
        isSavingOrLoading = false
    }
    
    /// Load from iCloud with retry mechanism
    private func loadFromiCloud(for date: Date? = nil) async {
        guard !isSavingOrLoading else {
            return
        }
        
        isSavingOrLoading = true
        showRetryDownload = false
        
        let targetDate = date ?? currentDate
        
        // Clear cache to ensure we get the latest data from iCloud
        // This is important for the sync functionality to work properly
        JournalStorageNew.shared.clearCache(for: targetDate)
        
        // Load drawing with fresh data from iCloud
        if let drawing = await JournalStorageNew.shared.load(for: targetDate) {
            canvasView.drawing = drawing
        } else {
            canvasView.drawing = PKDrawing()
        }
        
        // Load photos with fresh data
        await loadPhotos(for: targetDate)
        
        loadedDate = targetDate
        contentDate = targetDate  // Set the content date to the loaded date
        
        // Print detailed render information
        print("📖 JOURNAL RENDER - Loading content for date: \(formatDateForDisplay(targetDate))")
        print("📖 JOURNAL RENDER - Drawing strokes: \(canvasView.drawing.strokes.count)")
        print("📖 JOURNAL RENDER - Photos count: \(photos.count)")
        if !photos.isEmpty {
            for (index, photo) in photos.enumerated() {
                print("📖 JOURNAL RENDER - Photo \(index + 1): \(photo.id) (\(Int(photo.size.width))x\(Int(photo.size.height)))")
            }
        }
        
        isSavingOrLoading = false
    }
    
    /// Check if there are unsaved changes by comparing with saved content
    private func hasUnsavedChanges() async -> Bool {
        // Check if there are any photos or if the drawing has strokes
        let hasCurrentContent = !photos.isEmpty || !canvasView.drawing.strokes.isEmpty
        
        if !hasCurrentContent {
            return false
        }
        
        // Load the saved content from iCloud to compare
        let savedDrawing = await JournalStorageNew.shared.load(for: currentDate)
        let savedPhotos = await loadSavedPhotos(for: currentDate)
        
        // Compare drawings
        let drawingChanged = !areDrawingsEqual(canvasView.drawing, savedDrawing ?? PKDrawing())
        
        // Compare photos
        let photosChanged = !arePhotosEqual(photos, savedPhotos)
        
        return drawingChanged || photosChanged
    }
    
    /// Compare two PKDrawing objects for equality
    private func areDrawingsEqual(_ drawing1: PKDrawing, _ drawing2: PKDrawing) -> Bool {
        // Compare stroke counts first (quick check)
        if drawing1.strokes.count != drawing2.strokes.count {
            return false
        }
        
        // If both are empty, they're equal
        if drawing1.strokes.isEmpty && drawing2.strokes.isEmpty {
            return true
        }
        
        // Compare data representations for exact equality
        let data1 = drawing1.dataRepresentation()
        let data2 = drawing2.dataRepresentation()
        return data1 == data2
    }
    
    /// Compare two photo arrays for equality
    private func arePhotosEqual(_ photos1: [JournalPhoto], _ photos2: [JournalPhoto]) -> Bool {
        if photos1.count != photos2.count {
            return false
        }
        
        // Compare by ID and size (assuming photos with same ID and size are the same)
        let sorted1 = photos1.sorted { $0.id < $1.id }
        let sorted2 = photos2.sorted { $0.id < $1.id }
        
        for (photo1, photo2) in zip(sorted1, sorted2) {
            if photo1.id != photo2.id || photo1.size != photo2.size {
                return false
            }
        }
        
        return true
    }
    
    /// Load saved photos from iCloud for comparison
    private func loadSavedPhotos(for date: Date) async -> [JournalPhoto] {
        // This is a simplified version - in a real implementation,
        // you'd load the actual saved photos from iCloud
        // For now, return empty array as we don't have the full photo loading logic here
        return []
    }
    
    /// Refresh journal content from iCloud
    private func refreshFromiCloud() async {
        let hasChanges = await hasUnsavedChanges()
        if hasChanges {
            showUnsavedChangesAlert = true
            return
        }
        
        await loadFromiCloud(for: currentDate)
    }
    
    /// Date switching - saves current content then loads new content
    private func switchToDate(_ newDate: Date) async {
        guard !isSavingOrLoading else {
            return
        }
        
        isSavingOrLoading = true
        
        // Save current content before switching dates
        await saveToiCloud()
        
        // Load new content from iCloud for the specific date
        await loadFromiCloud(for: newDate)
        
        isSavingOrLoading = false
    }
    
    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: currentDate)
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
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
                            await loadFromiCloud(for: currentDate)
                        }
                    }
                    .onDisappear {
                        // Auto-save when view disappears
                        Task { @MainActor in
                            await saveToiCloud()
                        }
                    }
        .onChange(of: currentDate) { newValue in
            Task { @MainActor in
                await switchToDate(newValue)
            }
        }
        .onChange(of: pickerItems) { newValue in
            if !newValue.isEmpty {
                loadSelectedPhotos()
            }
        }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshJournalContent"))) { _ in
                        Task { @MainActor in
                            // Refresh journal content when notification is received
                            await switchToDate(currentDate)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerJournalAutoSave"))) { notification in
                        Task { @MainActor in
                            // Trigger auto-save when requested by day views
                            await saveToiCloud()
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
                                await loadFromiCloud(for: currentDate)
                            }
                        }
                        .onChange(of: currentDate) { newValue in
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
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerJournalAutoSave"))) { notification in
                            Task { @MainActor in
                                // Trigger auto-save when requested by day views
                                await saveToiCloud()
                            }
                        }
                        .onDisappear {
                            // Auto-save when view disappears
                            Task { @MainActor in
                                await saveToiCloud()
                            }
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
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard Changes", role: .destructive) {
                Task { @MainActor in
                    await loadFromiCloud(for: currentDate)
                }
            }
        } message: {
            Text("You have unsaved changes. Refreshing will discard your current work. Do you want to continue?")
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
                
                // Refresh button
                Button(action: {
                    Task { @MainActor in
                        await refreshFromiCloud()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
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
                        // Update content date to current date when user draws
                        contentDate = currentDate
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
            
            // Photos overlay
            photosOverlay
            
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
                        .onAppear {
                            print("📝 JournalView: Drawing content for date: \(currentDate)")
                        }
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: {
                        Task { @MainActor in
                            await loadFromiCloud(for: currentDate)
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
                print("🖼️ Canvas onAppear: photos count = \(photos.count)")
                for (idx, photo) in photos.enumerated() {
                    print("🖼️ Photo \(idx): position = \(photo.position), size = \(photo.size)")
                }
            }
            .onChange(of: newSize) { size in
                // Update size and reflow when layout changes
                let oldSize = canvasSize
                canvasSize = size
                
                // Debug: Log when canvas size changes
                if oldSize.width != size.width || oldSize.height != size.height {
                    print("📐 Canvas size changed: \(oldSize) -> \(size), photos count: \(photos.count)")
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            Task { @MainActor in
                switch newPhase {
                case .inactive, .background:
                    // Auto-save when app goes to background or becomes inactive
                    await saveToiCloud()
                case .active:
                    // Reload content when becoming active
                    await switchToDate(currentDate)
                @unknown default:
                    break
                }
            }
        }
    }
    
    // Photos overlay for absolute positioning
    private var photosOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(
                ZStack {
                    ForEach(photos.indices, id: \.self) { idx in
                        DraggablePhotoView(
                            photo: $photos[idx],
                            onDelete: {
                                photos.remove(at: idx)
                            },
                            onChanged: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    savePhotos()
                                }
                            },
                            canvasSize: canvasSize
                        )
                        .onAppear {
                            print("🖼️ DraggablePhotoView created:")
                            print("  - Photo position: \(photos[idx].position)")
                            print("  - Photo size: \(photos[idx].size)")
                            print("  - Canvas size: \(canvasSize)")
                        }
                    }
                }
            )
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
            
            // Always write a metadata file (can be empty) so existence checks are consistent
            // across sessions. Remove per-photo images only when clearing all.
            if photos.isEmpty {
                let empty: [PhotoMeta] = []
                let jsonData = try JSONEncoder().encode(empty)
                try jsonData.write(to: metadataURL(for: targetDate), options: .atomic)
                return
            }
            
            var metas: [PhotoMeta] = []
            let photoDir = photosDirectory()
            
            for photo in photos {
                let id = photo.id.uuidString
                let fileName = id + ".png"
                let fileURL = photoDir.appendingPathComponent(fileName)
                
                
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
        } catch {
            // Silently fail - photos will be retried on next save
        }
    }
    private func loadPhotos(for date: Date? = nil) async {
        let targetDate = date ?? currentDate
        
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
                
                // Check if metadata file exists
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return
                }
                
                // Apply same robust iCloud handling as drawings
                await ensureFileDownloadedWithRetry(url: url, maxRetries: 3)
                
                // Load metadata with timeout protection
                let data = try await withTimeout(seconds: 2) {
                    try Data(contentsOf: url)
                }
                let metas = try JSONDecoder().decode([PhotoMeta].self, from: data)
                
                // If no photos found in iCloud, check local storage as fallback
                if metas.isEmpty {
                    let localURL = JournalManager.shared.localPhotosURL.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        do {
                            let localData = try await withTimeout(seconds: 1) {
                                try Data(contentsOf: localURL)
                            }
                            let localMetas = try JSONDecoder().decode([PhotoMeta].self, from: localData)
                            
                            // Copy to iCloud for future use
                            try localData.write(to: url, options: .atomic)
                            
                            // Load photos in parallel for better performance
                            let loadedPhotos = await loadPhotosInParallel(metas: localMetas)
                            photos = loadedPhotos
                            return
                        } catch {
                            // Silently fail - will retry on next attempt
                        }
                    }
                }
                
                // Load photos in parallel for better performance
                let loadedPhotos = await loadPhotosInParallel(metas: metas)
                photos = loadedPhotos
                return
                
            } catch {
                if attempt < maxRetries {
                    // Exponential backoff: 1s, 2s
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }
    
    /// Load individual photo with retry logic
    private func loadPhotoWithRetry(meta: PhotoMeta, maxRetries: Int) async -> JournalPhoto? {
        let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
        
        for attempt in 1...maxRetries {
            do {
                // Check if file exists
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                
                // Ensure photo file is downloaded if in iCloud
                await ensureFileDownloaded(url: fileURL)
                
                // Load photo data with timeout protection
                let data = try await withTimeout(seconds: 1.5) {
                    try Data(contentsOf: fileURL)
                }
                guard let uiImg = UIImage(data: data) else {
                    return nil
                }
                
                // Calculate position and size
                let width = canvasSize.width > 0 ? canvasSize.width : 600 // Use reasonable default
                let height = canvasSize.height > 0 ? canvasSize.height : 800 // Use reasonable default
                let posX: CGFloat
                let posY: CGFloat
                let sizeW: CGFloat
                let sizeH: CGFloat
                
                // Always use absolute coordinates for fixed positions like drawings
                // Don't recalculate positions based on canvas size changes
                posX = CGFloat(meta.x)
                posY = CGFloat(meta.y)
                sizeW = CGFloat(meta.width)
                sizeH = CGFloat(meta.height)
                
                // Validate dimensions to prevent "Invalid frame dimension" errors
                let validWidth = max(1.0, sizeW.isFinite ? sizeW : 120.0)
                let validHeight = max(1.0, sizeH.isFinite ? sizeH : 120.0)
                // Clamp positions to reasonable bounds to ensure photo is visible
                // Photos outside bounds will be clamped to a visible area
                let validPosX = posX.isFinite ? max(0, min(width, posX)) : 150.0
                let validPosY = posY.isFinite ? max(0, min(height, posY)) : 150.0
                
                // Cache the loaded image for future use
                let cacheKey = "\(meta.id)_\(meta.fileName)"
                ImageCache.shared.cacheImage(uiImg, for: cacheKey)
                
                let photo = JournalPhoto(
                    id: UUID(uuidString: meta.id) ?? UUID(),
                    image: uiImg,
                    position: CGPoint(x: validPosX, y: validPosY),
                    size: CGSize(width: validWidth, height: validHeight),
                    rotation: Angle(radians: meta.rotation)
                )
                
                print("🖼️ Photo loaded: position (\(validPosX), \(validPosY)), canvas size (\(width)x\(height))")
                
                return photo
                
            } catch {
                if attempt < maxRetries {
                    let delay = UInt64(500_000_000) // 0.5 seconds
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        return nil
    }
    
    /// Ensure iCloud file is fully downloaded with robust retry logic
    private func ensureFileDownloadedWithRetry(url: URL, maxRetries: Int) async {
        for _ in 1...maxRetries {
            // Check if file is in iCloud
            var isUbiquitous: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            let isInCloud = (isUbiquitous as? Bool) == true
            
            if isInCloud {
                // Start download without blocking
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                // Wait for download with shorter timeout to prevent freezing
                let timeout: TimeInterval = 1.5
                let startTime = Date()
                
                while Date().timeIntervalSince(startTime) < timeout {
                    var downloadStatus: AnyObject?
                    try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
                    
                    if let status = downloadStatus as? URLUbiquitousItemDownloadingStatus {
                        if status == .current {
                            return
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds (faster polling)
                }
                
                // Timeout reached, proceed with available data
            }
            return
        }
        
        // Failed to download after max retries
    }
    
    /// Helper function to add timeout protection to async operations
    private func withTimeout<T>(seconds: Double, operation: @escaping () throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    /// Load multiple photos in parallel for better performance with caching
    private func loadPhotosInParallel(metas: [PhotoMeta]) async -> [JournalPhoto] {
        return await withTaskGroup(of: JournalPhoto?.self) { group in
            for meta in metas {
                group.addTask {
                    await self.loadPhotoWithCaching(meta: meta)
                }
            }
            
            var loadedPhotos: [JournalPhoto] = []
            for await photo in group {
                if let photo = photo {
                    loadedPhotos.append(photo)
                }
            }
            return loadedPhotos
        }
    }
    
    /// Load photo with caching for better performance
    private func loadPhotoWithCaching(meta: PhotoMeta) async -> JournalPhoto? {
        let cacheKey = "\(meta.id)_\(meta.fileName)"
        
        // Check cache first
        if let cachedImage = ImageCache.shared.image(for: cacheKey) {
            logPerformance("Photo loaded from cache: \(meta.fileName)")
            
            // Validate dimensions to prevent "Invalid frame dimension" errors
            let sizeW = meta.width
            let sizeH = meta.height
            let posX = meta.x
            let posY = meta.y
            
            // Use current canvas size for clamping when loading from cache
            let width = canvasSize.width > 0 ? canvasSize.width : 600
            let height = canvasSize.height > 0 ? canvasSize.height : 800
            
            let validWidth = max(1.0, sizeW.isFinite ? sizeW : 120.0)
            let validHeight = max(1.0, sizeH.isFinite ? sizeH : 120.0)
            // Clamp positions to reasonable bounds to ensure photo is visible
            let validPosX = posX.isFinite ? max(0, min(width, posX)) : 150.0
            let validPosY = posY.isFinite ? max(0, min(height, posY)) : 150.0
            
            return JournalPhoto(
                id: UUID(uuidString: meta.id) ?? UUID(),
                image: cachedImage,
                position: CGPoint(x: validPosX, y: validPosY),
                size: CGSize(width: validWidth, height: validHeight),
                rotation: Angle(radians: meta.rotation)
            )
        }
        
        // Load from file and cache
        return await loadPhotoWithRetry(meta: meta, maxRetries: 2)
    }
    
    /// Timeout error for async operations
    private struct TimeoutError: Error {
        let message = "Operation timed out"
    }
    
    /// Log all files in iCloud photos directory
    private func logiCloudPhotoFiles() async {
        // Debug function - no output needed
        let photosDir = photosDirectory()
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: [.fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [])
            
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
            }
            
            // Directory contents processed silently
        } catch {
            // Error listing directory - silently fail
        }
    }
    
    /// Ensure iCloud file is fully downloaded (optimized to prevent freezing)
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
        
        // Wait for download to complete with shorter timeout to prevent freezing
        let maxWaitTime: UInt64 = 1_500_000_000 // 1.5 seconds (reduced from 3)
        let checkInterval: UInt64 = 50_000_000 // 0.05 seconds (faster polling)
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
        
        // Timeout reached, proceed with available data
    }
    private func loadSelectedPhotos() {
        guard !pickerItems.isEmpty else { 
            return 
        }
        
        guard !isSavingOrLoading else {
            return
        }
        
        // Prevent duplicate processing
        guard !isProcessingPhotos else {
            return
        }
        
        isProcessingPhotos = true
        let targetDate = currentDate
        Task {
            var loadedPhotos: [JournalPhoto] = []
            
            for (index, item) in pickerItems.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self), let uiImg = UIImage(data: data) {
                    let position = CGPoint(x: 150, y: 150)
                    let size = CGSize(width: 120, height: 120)
                    let newPhoto = JournalPhoto(id: UUID(), image: uiImg, position: position, size: size, rotation: .zero)
                    
                    loadedPhotos.append(newPhoto)
                }
            }
            
            // Update photos array on main thread and save
            await MainActor.run {
                // Double-check we're still on the same date
                guard targetDate == currentDate else {
                    isProcessingPhotos = false
                    return
                }
                
                photos.append(contentsOf: loadedPhotos)
                pickerItems.removeAll()
                contentDate = targetDate  // Update content date when photos are added
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
        var canvasSize: CGSize = CGSize(width: 600, height: 800) // Default canvas size

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
                x: photo.position.x + dragOffset.width,
                y: photo.position.y + dragOffset.height
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
                    let newX = photo.position.x + value.translation.width
                    let newY = photo.position.y + value.translation.height
                    
                    // Allow photo to move freely - no bounds restrictions
                    let finalX = newX
                    let finalY = newY
                    
                    print("🖼️ Photo drag: from (\(photo.position.x), \(photo.position.y)) to (\(finalX), \(finalY))")
                    print("🖼️ Free movement: newY=\(newY), finalY=\(finalY)")
                    print("🖼️ Canvas size: \(canvasSize), Photo size: \(photo.size), Scale: \(scale)")
                    
                    photo.position.x = finalX
                    photo.position.y = finalY
                    
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
