import SwiftUI
import PDFKit
import PencilKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct JournalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var drawingManager = JournalDrawingManagerNew.shared
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
            if let drawing = await JournalStorageNew.shared.load(for: currentDate) {
                canvasView.drawing = drawing
            } else {
                canvasView.drawing = PKDrawing()
            }
        }
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
                        // Load content
                        loadDrawing()
                        loadPhotos()
                    }
                    .onDisappear {
                        Task { @MainActor in
                            // Save any pending changes
                            await drawingManager.saveImmediately()
                            savePhotos()
                        }
                    }
                    .onChange(of: currentDate) { oldValue, newValue in
                        print("🔄 JournalView (embedded): Date changed from \(oldValue) to \(newValue)")
                        Task { @MainActor in
                            // Save old content
                            await drawingManager.willSwitchDate()
                            savePhotos(for: oldValue)
                            
                            // Load new content
                            loadDrawing()
                            loadPhotos()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshJournalContent"))) { _ in
                        print("🔄 JournalView (embedded): Received RefreshJournalContent notification")
                        Task { @MainActor in
                            // Refresh journal content when notification is received
                            loadDrawing()
                            loadPhotos()
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
                            // Load content
                            loadDrawing()
                            loadPhotos()
                        }
                        .onChange(of: currentDate) { oldValue, newValue in
                            Task { @MainActor in
                                // Save old content
                                await drawingManager.willSwitchDate()
                                savePhotos(for: oldValue)
                                
                                // Load new content
                                loadDrawing()
                                loadPhotos()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshJournalContent"))) { _ in
                            Task { @MainActor in
                                // Refresh journal content when notification is received
                                loadDrawing()
                                loadPhotos()
                            }
                        }
                        .onDisappear {
                            Task { @MainActor in
                                // Save any pending changes
                                await drawingManager.saveImmediately()
                                savePhotos()
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
    }

    // MARK: - Top toolbar inline (all icons on same line as title)
    private var topToolbar: some View {
        HStack {
            Text("Journal")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 16) {
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
            Color.white
                .ignoresSafeArea()

            // PencilKit canvas overlay
            PencilKitView(
                canvasView: $canvasView,
                showsToolPicker: showToolPicker,
                onDrawingChanged: {
                    Task { @MainActor in
                        await drawingManager.handleDrawingChange(date: currentDate, drawing: canvasView.drawing)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .padding(1)
            )
            .overlay(alignment: .topTrailing) {
                if drawingManager.isSaving {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding()
                }
            }
                .ignoresSafeArea()
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
                loadPhotos()
            }
        }
        .onChange(of: pickerItems) { _ in
            loadSelectedPhotos()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                switch newPhase {
                case .inactive, .background:
                    // Save when app goes to background or becomes inactive
                    await drawingManager.saveImmediately()
                    savePhotos()
                case .active:
                    // Reload content when becoming active
                    loadDrawing()
                    loadPhotos()
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
    /// Uses iCloud if available, falls back to local
    private func photosDirectory() -> URL {
        // Try iCloud first
        if let iCloudRoot = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("journal_photos") {
            try? FileManager.default.createDirectory(at: iCloudRoot, withIntermediateDirectories: true)
            return iCloudRoot
        }
        
        // Fallback to local
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("journal_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private func metadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Use UTC so filenames are consistent across devices/timezones
        formatter.timeZone = TimeZone.current // Use local timezone to match drawings
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_photos.json"
        return photosDirectory().appendingPathComponent(name)
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
    private func loadPhotos(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        photos.removeAll()
        let url = metadataURL(for: targetDate)
        
        // For iCloud files, check download status
        let fm = FileManager.default
        var isUbiquitous: AnyObject?
        try? (url as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
        if (isUbiquitous as? Bool) == true {
            // Start downloading if not already downloaded
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
        
        guard let data = try? Data(contentsOf: url), let metas = try? JSONDecoder().decode([PhotoMeta].self, from: data) else { 
            return 
        }
        for meta in metas {
            let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
            
            // Check if file exists
            let fileExists = fm.fileExists(atPath: fileURL.path)
            
            if !fileExists {
                continue
            }
            
            // For iCloud photo files, ensure they're downloaded
            try? (fileURL as NSURL).getResourceValue(&isUbiquitous, forKey: URLResourceKey.isUbiquitousItemKey)
            let isInCloud = (isUbiquitous as? Bool) == true
            
            if isInCloud {
                try? fm.startDownloadingUbiquitousItem(at: fileURL)
            }
            
            guard let data = try? Data(contentsOf: fileURL), let uiImg = UIImage(data: data) else {
                continue
            }
            let width = canvasSize.width > 0 ? canvasSize.width : UIScreen.main.bounds.width
            let height = canvasSize.height > 0 ? canvasSize.height : UIScreen.main.bounds.height
            let posX: CGFloat
            let posY: CGFloat
            let sizeW: CGFloat
            let sizeH: CGFloat
            if let nx = meta.nx, let ny = meta.ny, let _ = meta.nw, let _ = meta.nh {
                // Keep photo size constant across divider/canvas size changes.
                // Reflow position using normalized coordinates only.
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
            let photo = JournalPhoto(id: UUID(uuidString: meta.id) ?? UUID(), image: uiImg, position: CGPoint(x: posX, y: posY), size: CGSize(width: sizeW, height: sizeH), rotation: Angle(radians: meta.rotation))
            photos.append(photo)
        }
    }
    private func loadSelectedPhotos() {
        guard !pickerItems.isEmpty else { return }
        for item in pickerItems {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let uiImg = UIImage(data: data) {
                    let position = CGPoint(x: 150, y: 150)
                    let size = CGSize(width: 120, height: 120)
                    let newPhoto = JournalPhoto(id: UUID(), image: uiImg, position: position, size: size, rotation: .zero)
                    photos.append(newPhoto)
                }
            }
        }
        pickerItems.removeAll()
        savePhotos()
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
                    .frame(width: photo.size.width * scale, height: photo.size.height * scale)
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
            .position(x: photo.position.x + dragOffset.width, y: photo.position.y + dragOffset.height)
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
