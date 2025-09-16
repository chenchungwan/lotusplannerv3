import SwiftUI
import PDFKit
import PencilKit
import PhotosUI
import UIKit

struct JournalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentDate: Date
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
    
    init(currentDate: Date, embedded: Bool = false, layoutType: JournalLayoutType = .compact) {
        _currentDate = State(initialValue: currentDate)
        _previousDate = State(initialValue: currentDate)
        self.embedded = embedded
        self.layoutType = layoutType
    }
    
    // Interval is always day for journal navigation (reuse same step logic)
    private func step(_ direction: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: direction, to: currentDate) else { return }
        // Save drawing for current date before switching
        JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                        savePhotos()
        previousDate = currentDate
        currentDate = newDate
        loadDrawing()
    }

    private func loadDrawing() {
        // Load on main to avoid race with view lifecycle
        DispatchQueue.main.async {
            if let drawing = JournalManager.shared.loadDrawing(for: currentDate) {
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
                }
                    .onAppear {
                        loadDrawing()
                        loadPhotos()
                        // Ensure local content is moved to iCloud when available (embedded path)
                        JournalManager.shared.migrateLocalToICloudIfNeeded()
                        JournalManager.shared.startICloudMonitoring()
                        JournalManager.shared.ensureICloudReady(for: currentDate)
                        
                        // Listen for refresh notifications
                        NotificationCenter.default.addObserver(
                            forName: Notification.Name("RefreshJournalContent"),
                            object: nil,
                            queue: .main
                        ) { _ in
                            loadDrawing()
                            loadPhotos()
                        }
                    }
                    .onDisappear {
                        JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                        savePhotos()
                        JournalManager.shared.stopICloudMonitoring()
                    }
                    .onChange(of: currentDate) { oldValue, newValue in
                        // Save old content
                        JournalManager.shared.saveDrawing(for: oldValue, drawing: canvasView.drawing)
                        savePhotos(for: oldValue)

                        // Load new content
                        loadDrawing()
                        loadPhotos()
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 8) {
                        topToolbar
                        canvasContent
                    }
                        .navigationTitle("")
                        .toolbarTitleDisplayMode(.inline)
                        .onAppear { loadDrawing(); loadPhotos() }
                        .task {
                            JournalManager.shared.migrateLocalToICloudIfNeeded()
                            JournalManager.shared.startICloudMonitoring()
                            JournalManager.shared.ensureICloudReady(for: currentDate)
                        }
                        .onChange(of: currentDate) { oldValue, newValue in
                            JournalManager.shared.saveDrawing(for: oldValue, drawing: canvasView.drawing)
                            savePhotos(for: oldValue)
                            loadDrawing()
                            loadPhotos()
                        }
                        .onDisappear {
                            // Persist when view leaves hierarchy (e.g., day changed)
                            JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                            savePhotos()
                            JournalManager.shared.stopICloudMonitoring()
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
                                    JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                                    savePhotos()
                                    dismiss()
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
            PencilKitView(canvasView: $canvasView, showsToolPicker: showToolPicker)
                .ignoresSafeArea()
            // Movable photos overlay
            ForEach(photos.indices, id: \.self) { idx in
                DraggablePhotoView(photo: $photos[idx]) {
                    photos.remove(at: idx)
                }
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
    }
    
    // (Old floating controlButtons removed)
    
    // MARK: - Clear Journal
    private func clearJournal() {
        canvasView.drawing = PKDrawing()
        photos.removeAll()
    }

    private func exportJournal() {
        // Save current drawing/photos first
        JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
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
    /// – If the user has iCloud Drive enabled for this app we store them in the
    ///   app’s ubiquity container so they sync across devices.
    /// – Otherwise we fall back to the local Documents directory so the feature
    ///   still works offline / on simulator.
    private func photosDirectory() -> URL {
        // Persist locally to ensure reliability across sessions (matches drawing storage)
        let rootDocs = JournalManager.shared.storageRootURL()
        let dir = rootDocs.appendingPathComponent("journal_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private func metadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_photos.json"
        return photosDirectory().appendingPathComponent(name)
    }
    
    private func savePhotos(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        // Always write a metadata file (can be empty) so existence checks are consistent
        // across sessions. Remove per-photo images only when clearing all.
        if photos.isEmpty {
            let empty: [PhotoMeta] = []
            if let jsonData = try? JSONEncoder().encode(empty) {
                try? jsonData.write(to: metadataURL(for: targetDate), options: .atomic)
            }
            return
        }
        var metas: [PhotoMeta] = []
        for photo in photos {
            let id = photo.id.uuidString
            let fileName = id + ".png"
            let fileURL = photosDirectory().appendingPathComponent(fileName)
            if let data = photo.image.pngData() {
                try? data.write(to: fileURL, options: .atomic)
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
        if let jsonData = try? JSONEncoder().encode(metas) {
            try? jsonData.write(to: metadataURL(for: targetDate), options: .atomic)
        }
        // Ensure iCloud migration picks up newly saved photos/metadata
        JournalManager.shared.migrateLocalToICloudIfNeeded()
    }
    private func loadPhotos(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        photos.removeAll()
        let url = metadataURL(for: targetDate)
        guard let data = try? Data(contentsOf: url), let metas = try? JSONDecoder().decode([PhotoMeta].self, from: data) else { return }
        for meta in metas {
            let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
            var dataOpt = try? Data(contentsOf: fileURL)
            if dataOpt == nil {
                // Try alternate roots if not found
                let iCloudRoot = JournalManager.shared.storageRootURL()
                let alt = iCloudRoot.appendingPathComponent("journal_photos").appendingPathComponent(meta.fileName)
                dataOpt = try? Data(contentsOf: alt)
            }
            guard let data = dataOpt, let uiImg = UIImage(data: data) else { continue }
            let width = canvasSize.width > 0 ? canvasSize.width : UIScreen.main.bounds.width
            let height = canvasSize.height > 0 ? canvasSize.height : UIScreen.main.bounds.height
            let posX: CGFloat
            let posY: CGFloat
            let sizeW: CGFloat
            let sizeH: CGFloat
            if let nx = meta.nx, let ny = meta.ny, let nw = meta.nw, let nh = meta.nh {
                posX = CGFloat(nx) * width
                posY = CGFloat(ny) * height
                sizeW = CGFloat(nw) * width
                sizeH = CGFloat(nh) * height
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
                }
        }
    }
    
}



#Preview {
    JournalView(currentDate: Date())
} 
