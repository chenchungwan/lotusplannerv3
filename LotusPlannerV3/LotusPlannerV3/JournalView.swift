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
    /// Text annotations placed on the canvas.
    @State private var textAnnotations: [JournalTextAnnotation] = []
    /// Whether the text input alert is showing.
    @State private var showTextInput: Bool = false
    /// The annotation currently being edited (nil = new annotation).
    @State private var editingAnnotationId: UUID? = nil
    /// Text field content for the text input alert.
    @State private var annotationInputText: String = ""
    /// Show confirmation alert before erasing journal content
    @State private var showingEraseConfirmation = false
    /// Loading states for sync status indicators
    @State private var isLoadingDrawings = false
    @State private var isLoadingPhotos = false
    /// Prevents concurrent save/load operations
    @State private var isSavingOrLoading = false
    /// Sync state for refresh button
    @State private var isSyncing = false
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
            return
        }

        isLoadingDrawings = true
        logPerformance("Loading drawing for journal page date: \(currentDate)")

        // Ensure we're loading for the correct date
        let targetDate = currentDate

        // Start monitoring file for iCloud changes
        // Note: Monitoring will post a notification that we listen to below
        JournalStorageNew.shared.monitorFile(for: targetDate)

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
            await savePhotos(for: saveDate)

            // Save text annotations
            await saveTextAnnotations(for: saveDate)

            saveStatus = .saved
            
            // Clear save status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if case .saved = saveStatus {
                    saveStatus = .idle
                }
            }
            
        } catch {
            saveStatus = .error(error.localizedDescription)
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

        // Load text annotations
        await loadTextAnnotations(for: targetDate)

        loadedDate = targetDate
        contentDate = targetDate  // Set the content date to the loaded date

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
        // Start sync indicator
        isSyncing = true

        let hasChanges = await hasUnsavedChanges()
        if hasChanges {
            showUnsavedChangesAlert = true
            isSyncing = false
            return
        }

        await loadFromiCloud(for: currentDate)

        // Stop sync indicator
        isSyncing = false
    }
    
    /// Date switching - saves current content then loads new content
    private func switchToDate(_ newDate: Date) async {
        guard !isSavingOrLoading else {
            return
        }

        isSavingOrLoading = true

        // Stop monitoring the old date
        JournalStorageNew.shared.stopMonitoring(for: previousDate)

        // Save current content before switching dates
        await saveToiCloud()

        // Update previous date
        previousDate = currentDate

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
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("JournalFileChangedFromiCloud"))) { notification in
                        Task { @MainActor in
                            // Reload drawing when file changes from iCloud
                            if let changedDate = notification.userInfo?["date"] as? Date,
                               Calendar.current.isDate(changedDate, inSameDayAs: currentDate) {
                                devLog("📲 JournalView: Drawing file changed from iCloud for current date, reloading...")
                                await loadFromiCloud(for: currentDate)
                            }
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
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("JournalFileChangedFromiCloud"))) { notification in
                            Task { @MainActor in
                                // Reload drawing when file changes from iCloud
                                if let changedDate = notification.userInfo?["date"] as? Date,
                                   Calendar.current.isDate(changedDate, inSameDayAs: currentDate) {
                                    devLog("📲 JournalView: Drawing file changed from iCloud for current date, reloading...")
                                    await loadFromiCloud(for: currentDate)
                                }
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
                                        Image(systemName: "pencil.and.scribble")
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
                                        await savePhotos()
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
        .alert(editingAnnotationId != nil ? "Edit Text" : "Add Text", isPresented: $showTextInput) {
            TextField("Enter text", text: $annotationInputText)
            Button(editingAnnotationId != nil ? "Save" : "Add") {
                let trimmed = annotationInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                if let editId = editingAnnotationId,
                   let idx = textAnnotations.firstIndex(where: { $0.id == editId }) {
                    // Update existing
                    textAnnotations[idx].text = trimmed
                } else {
                    // Create new at center of canvas
                    let center = CGPoint(
                        x: max(canvasSize.width / 2, 100),
                        y: max(canvasSize.height / 2, 100)
                    )
                    let newAnnotation = JournalTextAnnotation(
                        id: UUID(),
                        text: trimmed,
                        position: center,
                        size: CGSize(width: 200, height: 60)
                    )
                    textAnnotations.append(newAnnotation)
                }

                annotationInputText = ""
                editingAnnotationId = nil
                Task { @MainActor in
                    await saveTextAnnotations()
                }
            }
            Button("Cancel", role: .cancel) {
                annotationInputText = ""
                editingAnnotationId = nil
            }
        } message: {
            Text(editingAnnotationId != nil ? "Edit the text for this annotation." : "Enter text to place on the journal.")
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
                            return .accentColor
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
                    if isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.trianglehead.clockwise.icloud")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                }
                .disabled(isSavingOrLoading || isSyncing)
                .id(isSyncing)

                Button(action: {
                    editingAnnotationId = nil
                    annotationInputText = ""
                    showTextInput = true
                }) {
                    Image(systemName: "character.cursor.ibeam")
                }

                Button(action: { showToolPicker.toggle() }) {
                    Image(systemName: "pencil.and.scribble")
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

            // Text annotations overlay
            textAnnotationsOverlay

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
            }
            .onChange(of: newSize) { size in
                // Update size and reflow when layout changes
                canvasSize = size
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
                                    Task { @MainActor in
                                        await savePhotos()
                                    }
                                }
                            },
                            canvasSize: canvasSize
                        )
                    }
                }
            )
    }

    // Text annotations overlay for absolute positioning
    private var textAnnotationsOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(
                ZStack {
                    ForEach(textAnnotations.indices, id: \.self) { idx in
                        DraggableTextView(
                            annotation: $textAnnotations[idx],
                            onDelete: {
                                textAnnotations.remove(at: idx)
                                Task { @MainActor in
                                    await saveTextAnnotations()
                                }
                            },
                            onEdit: {
                                editingAnnotationId = textAnnotations[idx].id
                                annotationInputText = textAnnotations[idx].text
                                showTextInput = true
                            },
                            onChanged: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    Task { @MainActor in
                                        await saveTextAnnotations()
                                    }
                                }
                            }
                        )
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

        // Clear text annotations
        textAnnotations.removeAll()
        let textURL = textMetadataURL(for: currentDate)
        let emptyTexts: [TextAnnotationMeta] = []
        if let jsonData = try? JSONEncoder().encode(emptyTexts) {
            try? jsonData.write(to: textURL, options: .atomic)
        }
    }

    private func exportJournal() {
        // Save current drawing/photos first
        JournalStorageNew.shared.saveSync(canvasView.drawing, for: currentDate)
        Task { @MainActor in
            await savePhotos()
        }
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

    // MARK: - Text Annotation Persistence
    private struct TextAnnotationMeta: Codable {
        let id: String
        let text: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
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
    
    private func savePhotos(for date: Date? = nil) async {
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
            
            // Wait for iCloud upload to complete if file is in iCloud
            var isUbiquitous: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            if (isUbiquitous as? Bool) == true {
                await ensureFileUploadedForPhotos(url: url)
            }
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
                let data = try await withTimeout(seconds: 3) { // Increased from 2 to 3 seconds
                    try Data(contentsOf: url)
                }
                
                let metas = try JSONDecoder().decode([PhotoMeta].self, from: data)

                // If no photos found in iCloud, check local storage as fallback
                if metas.isEmpty {
                    devLog("🔍 No photos in iCloud, checking local storage...")
                    let localURL = JournalManager.shared.localPhotosURL.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        do {
                            let localData = try await withTimeout(seconds: 2) { // Increased from 1 to 2 seconds
                                try Data(contentsOf: localURL)
                            }
                            let localMetas = try JSONDecoder().decode([PhotoMeta].self, from: localData)

                            // Copy to iCloud for future use
                            try localData.write(to: url, options: .atomic)
                            devLog("💾 Copied local photos to iCloud")
                            
                            // Load photos in parallel for better performance
                            let loadedPhotos = await loadPhotosInParallel(metas: localMetas)
                            photos = loadedPhotos
                            return
                        } catch { }
                    }
                } else {
                    // Load photos in parallel for better performance
                    devLog("🔄 Loading \(metas.count) photos from iCloud...")
                    let loadedPhotos = await loadPhotosInParallel(metas: metas)
                    photos = loadedPhotos
                    devLog("✅ Successfully loaded \(loadedPhotos.count) photos from iCloud")
                    return
                }
                
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
                let data = try await withTimeout(seconds: 3.0) { // Increased from 1.5 to 3.0 seconds
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
        for attempt in 1...maxRetries {
            // Check if file is in iCloud
            var isUbiquitous: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            let isInCloud = (isUbiquitous as? Bool) == true
            
            if isInCloud {
                devLog("📱 iCloud download attempt \(attempt)/\(maxRetries) for: \(url.lastPathComponent)")
                
                // Start download without blocking
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                // Wait for download with longer timeout for better reliability
                let timeout: TimeInterval = 5.0 // Increased from 1.5 to 5.0 seconds
                let startTime = Date()
                
                while Date().timeIntervalSince(startTime) < timeout {
                    var downloadStatus: AnyObject?
                    try? (url as NSURL).getResourceValue(&downloadStatus, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
                    
                    if let status = downloadStatus as? URLUbiquitousItemDownloadingStatus {
                        if status == .current {
                            devLog("✅ iCloud download completed for: \(url.lastPathComponent)")
                            return
                        } else if status == .notDownloaded {
                            devLog("⚠️ iCloud file not downloaded yet: \(url.lastPathComponent)")
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds (slower polling for better reliability)
                }
                
                devLog("⏰ iCloud download timeout for: \(url.lastPathComponent) (attempt \(attempt)/\(maxRetries))")
                
                // If this is the last attempt, proceed with available data
                if attempt == maxRetries {
                    devLog("❌ iCloud download failed after \(maxRetries) attempts for: \(url.lastPathComponent)")
                    return
                }
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay between retries
            } else {
                devLog("📁 Local file (not in iCloud): \(url.lastPathComponent)")
                return
            }
        }
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
    
    /// Ensure iCloud file upload is complete after saving photos metadata
    /// Note: There's no direct API to check upload status, so we wait a reasonable time
    /// and verify the file exists locally to ensure it's queued for upload
    private func ensureFileUploadedForPhotos(url: URL) async {
        // Verify file exists locally (required for upload to start)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        // Wait a reasonable time for iCloud to queue and process the upload
        // iCloud uploads happen asynchronously, so we just ensure the file is saved locally
        let waitTime: UInt64 = 1_000_000_000 // 1 second
        try? await Task.sleep(nanoseconds: waitTime)
    }

    // MARK: - Text Annotation Persistence

    private func textMetadataURL(for date: Date) -> URL {
        return JournalManager.shared.textMetadataURL(for: date)
    }

    private func saveTextAnnotations(for date: Date? = nil) async {
        do {
            let targetDate = date ?? currentDate
            let url = textMetadataURL(for: targetDate)

            if textAnnotations.isEmpty {
                let empty: [TextAnnotationMeta] = []
                let jsonData = try JSONEncoder().encode(empty)
                try jsonData.write(to: url, options: .atomic)
                return
            }

            let cw = max(canvasSize.width, 1)
            let ch = max(canvasSize.height, 1)
            let metas = textAnnotations.map { ann in
                TextAnnotationMeta(
                    id: ann.id.uuidString,
                    text: ann.text,
                    x: ann.position.x,
                    y: ann.position.y,
                    width: ann.size.width,
                    height: ann.size.height,
                    nx: Double(ann.position.x / cw),
                    ny: Double(ann.position.y / ch),
                    nw: Double(ann.size.width / cw),
                    nh: Double(ann.size.height / ch),
                    cw: Double(cw),
                    ch: Double(ch)
                )
            }

            let jsonData = try JSONEncoder().encode(metas)
            try jsonData.write(to: url, options: .atomic)

            // Wait for iCloud upload
            var isUbiquitous: AnyObject?
            try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            if (isUbiquitous as? Bool) == true {
                await ensureFileUploadedForPhotos(url: url)
            }
        } catch {
            // Silently fail - will retry on next save
        }
    }

    private func loadTextAnnotations(for date: Date? = nil) async {
        let targetDate = date ?? currentDate
        textAnnotations.removeAll()

        let url = textMetadataURL(for: targetDate)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let metas = try JSONDecoder().decode([TextAnnotationMeta].self, from: data)

            var loaded: [JournalTextAnnotation] = []
            for meta in metas {
                guard let uuid = UUID(uuidString: meta.id) else { continue }

                var x = meta.x
                var y = meta.y
                var w = meta.width
                var h = meta.height

                // Use normalized coordinates if available and canvas size differs
                if let nx = meta.nx, let ny = meta.ny, let nw = meta.nw, let nh = meta.nh,
                   canvasSize.width > 0, canvasSize.height > 0 {
                    x = nx * canvasSize.width
                    y = ny * canvasSize.height
                    w = nw * canvasSize.width
                    h = nh * canvasSize.height
                }

                loaded.append(JournalTextAnnotation(
                    id: uuid,
                    text: meta.text,
                    position: CGPoint(x: max(0, x), y: max(0, y)),
                    size: CGSize(width: max(60, w), height: max(30, h))
                ))
            }

            textAnnotations = loaded
        } catch {
            // Silently fail - empty annotations for this date
        }
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
                
                // Reset processing flag
                isProcessingPhotos = false
            }
            
            // Save photos asynchronously outside the MainActor.run closure
            await savePhotos(for: targetDate) // Save to the journal page date, not current system date
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
        var canvasSize: CGSize = CGSize(width: 600, height: 800)

        @State private var dragOffset: CGSize = .zero
        @State private var rotationAngle: Angle = .zero
        @State private var showControls: Bool = false
        @State private var isCropping: Bool = false
        @State private var cropRect: CGRect = .zero
        // Track live resize offset per corner
        @State private var resizeOffset: CGSize = .zero

        private let minSize: CGFloat = 40
        private let handleSize: CGFloat = 20

        var body: some View {
            ZStack {
                if isCropping {
                    cropView
                } else {
                    normalView
                }
            }
            .position(
                x: photo.position.x + dragOffset.width,
                y: photo.position.y + dragOffset.height
            )
        }

        // MARK: - Normal (non-crop) view
        private var normalView: some View {
            ZStack {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: max(minSize, photo.size.width + resizeOffset.width),
                        height: max(minSize, photo.size.height + resizeOffset.height)
                    )
                    .clipped()
                    .rotationEffect(photo.rotation + rotationAngle)
                    .overlay(
                        showControls
                            ? RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.accentColor, lineWidth: 2)
                            : nil
                    )

                if showControls {
                    // Control buttons top-left
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Button(action: onDelete) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                                Button(action: {
                                    cropRect = CGRect(
                                        x: 0, y: 0,
                                        width: photo.size.width,
                                        height: photo.size.height
                                    )
                                    isCropping = true
                                }) {
                                    Image(systemName: "crop")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .background(Color.accentColor)
                                        .clipShape(Circle())
                                }
                            }
                            .offset(x: -8, y: -8)
                            Spacer()
                        }
                        Spacer()
                    }

                    // Corner resize handles
                    cornerHandle(corner: .bottomRight)
                    cornerHandle(corner: .bottomLeft)
                    cornerHandle(corner: .topRight)
                    cornerHandle(corner: .topLeft)
                }
            }
            .frame(
                width: max(minSize, photo.size.width + resizeOffset.width) + handleSize,
                height: max(minSize, photo.size.height + resizeOffset.height) + handleSize
            )
            .contentShape(Rectangle())
            .gesture(showControls ? nil : dragGesture)
            .simultaneousGesture(showControls ? nil : rotationGesture)
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }
        }

        // MARK: - Corner handle
        private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

        private func cornerHandle(corner: Corner) -> some View {
            let w = max(minSize, photo.size.width + resizeOffset.width)
            let h = max(minSize, photo.size.height + resizeOffset.height)

            let xOffset: CGFloat
            let yOffset: CGFloat
            switch corner {
            case .topLeft:     xOffset = -w / 2; yOffset = -h / 2
            case .topRight:    xOffset = w / 2;  yOffset = -h / 2
            case .bottomLeft:  xOffset = -w / 2; yOffset = h / 2
            case .bottomRight: xOffset = w / 2;  yOffset = h / 2
            }

            return Circle()
                .fill(Color.accentColor)
                .frame(width: handleSize, height: handleSize)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(x: xOffset, y: yOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let aspect = max(photo.size.width, 1) / max(photo.size.height, 1)
                            let dx = value.translation.width
                            let dy = value.translation.height
                            var dw: CGFloat = 0
                            var dh: CGFloat = 0

                            switch corner {
                            case .bottomRight:
                                dw = dx; dh = dw / aspect
                            case .bottomLeft:
                                dw = -dx; dh = dw / aspect
                            case .topRight:
                                dw = dx; dh = dw / aspect
                            case .topLeft:
                                dw = -dx; dh = dw / aspect
                            }

                            // Clamp so photo doesn't get smaller than minimum
                            if photo.size.width + dw < minSize { dw = minSize - photo.size.width }
                            if photo.size.height + dh < minSize { dh = minSize - photo.size.height }
                            resizeOffset = CGSize(width: dw, height: dh)
                        }
                        .onEnded { _ in
                            photo.size.width = max(minSize, photo.size.width + resizeOffset.width)
                            photo.size.height = max(minSize, photo.size.height + resizeOffset.height)
                            resizeOffset = .zero
                            onChanged()
                        }
                )
        }

        // MARK: - Crop view
        private var cropView: some View {
            let imgW = photo.size.width
            let imgH = photo.size.height

            return ZStack {
                // Full image dimmed
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imgW, height: imgH)
                    .clipped()
                    .overlay(Color.black.opacity(0.5))

                // Bright crop region
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imgW, height: imgH)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: cropRect.width, height: cropRect.height)
                            .offset(
                                x: cropRect.midX - imgW / 2,
                                y: cropRect.midY - imgH / 2
                            )
                    )

                // Crop rect border
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .offset(
                        x: cropRect.midX - imgW / 2,
                        y: cropRect.midY - imgH / 2
                    )

                // Crop corner handles
                cropCornerHandle(corner: .topLeft)
                cropCornerHandle(corner: .topRight)
                cropCornerHandle(corner: .bottomLeft)
                cropCornerHandle(corner: .bottomRight)

                // Done / Cancel buttons
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: {
                            isCropping = false
                        }) {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.gray)
                                .cornerRadius(6)
                        }
                        Button(action: applyCrop) {
                            Text("Done")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(width: imgW, height: imgH + 44)
        }

        private func cropCornerHandle(corner: Corner) -> some View {
            let imgW = photo.size.width
            let imgH = photo.size.height

            let xPos: CGFloat
            let yPos: CGFloat
            switch corner {
            case .topLeft:     xPos = cropRect.minX; yPos = cropRect.minY
            case .topRight:    xPos = cropRect.maxX; yPos = cropRect.minY
            case .bottomLeft:  xPos = cropRect.minX; yPos = cropRect.maxY
            case .bottomRight: xPos = cropRect.maxX; yPos = cropRect.maxY
            }

            return Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .offset(
                    x: xPos - imgW / 2,
                    y: yPos - imgH / 2
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            var rect = cropRect
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let minCrop: CGFloat = 30

                            switch corner {
                            case .topLeft:
                                let newX = max(0, rect.origin.x + dx)
                                let newY = max(0, rect.origin.y + dy)
                                let newW = rect.maxX - newX
                                let newH = rect.maxY - newY
                                if newW >= minCrop && newH >= minCrop {
                                    rect.origin.x = newX
                                    rect.origin.y = newY
                                    rect.size.width = newW
                                    rect.size.height = newH
                                }
                            case .topRight:
                                let newW = min(imgW - rect.origin.x, rect.width + dx)
                                let newY = max(0, rect.origin.y + dy)
                                let newH = rect.maxY - newY
                                if newW >= minCrop && newH >= minCrop {
                                    rect.size.width = newW
                                    rect.origin.y = newY
                                    rect.size.height = newH
                                }
                            case .bottomLeft:
                                let newX = max(0, rect.origin.x + dx)
                                let newW = rect.maxX - newX
                                let newH = min(imgH - rect.origin.y, rect.height + dy)
                                if newW >= minCrop && newH >= minCrop {
                                    rect.origin.x = newX
                                    rect.size.width = newW
                                    rect.size.height = newH
                                }
                            case .bottomRight:
                                let newW = min(imgW - rect.origin.x, rect.width + dx)
                                let newH = min(imgH - rect.origin.y, rect.height + dy)
                                if newW >= minCrop && newH >= minCrop {
                                    rect.size.width = newW
                                    rect.size.height = newH
                                }
                            }
                            cropRect = rect
                        }
                )
        }

        // MARK: - Apply crop
        private func applyCrop() {
            let scaleX = photo.image.size.width / photo.size.width
            let scaleY = photo.image.size.height / photo.size.height

            let scaledRect = CGRect(
                x: cropRect.origin.x * scaleX,
                y: cropRect.origin.y * scaleY,
                width: cropRect.width * scaleX,
                height: cropRect.height * scaleY
            )

            if let cgImage = photo.image.cgImage?.cropping(to: scaledRect) {
                let croppedImage = UIImage(cgImage: cgImage, scale: photo.image.scale, orientation: photo.image.imageOrientation)
                photo.image = croppedImage
                photo.size = CGSize(width: cropRect.width, height: cropRect.height)
            }

            isCropping = false
            showControls = false
            onChanged()
        }

        // MARK: - Gestures
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

    // MARK: - Text Annotation model & view
    struct JournalTextAnnotation: Identifiable {
        let id: UUID
        var text: String
        var position: CGPoint
        var size: CGSize
    }

    struct DraggableTextView: View {
        @Binding var annotation: JournalTextAnnotation
        var onDelete: () -> Void
        var onEdit: () -> Void
        var onChanged: () -> Void = {}

        @State private var dragOffset: CGSize = .zero
        @State private var showControls: Bool = false

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Text(annotation.text)
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .padding(8)
                    .frame(
                        minWidth: 60,
                        maxWidth: max(60, annotation.size.width),
                        alignment: .topLeading
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.white.opacity(0.85))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showControls ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: showControls ? 2 : 1)
                    )

                if showControls {
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.accentColor)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    .offset(x: 8, y: -8)
                }
            }
            .position(
                x: annotation.position.x + dragOffset.width,
                y: annotation.position.y + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        annotation.position.x += value.translation.width
                        annotation.position.y += value.translation.height
                        dragOffset = .zero
                        onChanged()
                    }
            )
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }
        }
    }

}

#Preview {
    JournalView(currentDate: .constant(Date()))
}
