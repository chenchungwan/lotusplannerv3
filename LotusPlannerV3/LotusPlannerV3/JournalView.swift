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
        if let drawing = JournalManager.shared.loadDrawing(for: currentDate) {
            canvasView.drawing = drawing
        } else {
            canvasView.drawing = PKDrawing()
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
                                }
                            }
                            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
        ZStack {
            // Observe photo picker selection
        
            // PDF background (fallback to blank when file missing)
            if let url = JournalManager.shared.backgroundPDFURL(for: layoutType),
               let doc = PDFDocument(url: url) {
                PDFKitView(document: doc)
                    .ignoresSafeArea()
            } else {
                Color.clear
            }

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
    }
    
    /// Directory where per-day photo PNGs are stored.
    /// – If the user has iCloud Drive enabled for this app we store them in the
    ///   app’s ubiquity container so they sync across devices.
    /// – Otherwise we fall back to the local Documents directory so the feature
    ///   still works offline / on simulator.
    private func photosDirectory() -> URL {
        // Root Documents dir (iCloud if available)
        let rootDocs: URL = {
            if let ubiquityDocs = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
                return ubiquityDocs
            }
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }()

        let dir = rootDocs.appendingPathComponent("journal_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private func metadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_photos.json"
        return photosDirectory().appendingPathComponent(name)
    }
    
    private func savePhotos(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        guard !photos.isEmpty else {
            try? FileManager.default.removeItem(at: metadataURL(for: targetDate))
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
            metas.append(PhotoMeta(id: id, fileName: fileName, x: photo.position.x, y: photo.position.y, width: photo.size.width, height: photo.size.height, rotation: photo.rotation.radians))
        }
        if let jsonData = try? JSONEncoder().encode(metas) {
            try? jsonData.write(to: metadataURL(for: targetDate), options: .atomic)
        }
    }
    private func loadPhotos(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        photos.removeAll()
        let url = metadataURL(for: targetDate)
        guard let data = try? Data(contentsOf: url), let metas = try? JSONDecoder().decode([PhotoMeta].self, from: data) else { return }
        for meta in metas {
            let fileURL = photosDirectory().appendingPathComponent(meta.fileName)
            if let data = try? Data(contentsOf: fileURL), let uiImg = UIImage(data: data) {
                let photo = JournalPhoto(id: UUID(uuidString: meta.id) ?? UUID(), image: uiImg, position: CGPoint(x: meta.x, y: meta.y), size: CGSize(width: meta.width, height: meta.height), rotation: Angle(radians: meta.rotation))
                photos.append(photo)
            }
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

// PDFKit SwiftUI wrapper
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.backgroundColor = UIColor.clear
        pdfView.isUserInteractionEnabled = false // static background
        return pdfView
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}


#Preview {
    JournalView(currentDate: Date())
} 
