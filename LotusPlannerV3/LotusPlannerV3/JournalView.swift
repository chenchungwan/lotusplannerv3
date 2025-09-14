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
    /// Text elements placed on the canvas.
    @State private var textElements: [JournalText] = []
    /// Show confirmation alert before erasing journal content
    @State private var showingEraseConfirmation = false
    /// Whether text input mode is active
    @State private var isTextModeActive = false

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
                        loadTextElements()
                        
                        // Listen for refresh notifications
                        NotificationCenter.default.addObserver(
                            forName: Notification.Name("RefreshJournalContent"),
                            object: nil,
                            queue: .main
                        ) { _ in
                            loadDrawing()
                            loadPhotos()
                            loadTextElements()
                        }
                    }
                    .onDisappear {
                        JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                        savePhotos()
                        saveTextElements()
                    }
                    .onChange(of: currentDate) { oldValue, newValue in
                        // Save old content
                        JournalManager.shared.saveDrawing(for: oldValue, drawing: canvasView.drawing)
                        savePhotos(for: oldValue)
                        saveTextElements(for: oldValue)

                        // Load new content
                        loadDrawing()
                        loadPhotos()
                        loadTextElements()
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 8) {
                        topToolbar
                        canvasContent
                    }
                        .navigationTitle("")
                        .toolbarTitleDisplayMode(.inline)
                        .onAppear { loadDrawing(); loadPhotos(); loadTextElements() }
                        .onChange(of: currentDate) { oldValue, newValue in
                            JournalManager.shared.saveDrawing(for: oldValue, drawing: canvasView.drawing)
                            savePhotos(for: oldValue)
                            saveTextElements(for: oldValue)
                            loadDrawing()
                            loadPhotos()
                            loadTextElements()
                        }
                        .onDisappear {
                            // Persist when view leaves hierarchy (e.g., day changed)
                            JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
                            savePhotos()
                            saveTextElements()
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

    // MARK: - Top toolbar inline (left: export; right: text, pencil, photo, trash)
    private var topToolbar: some View {
        GeometryReader { geo in
            HStack(alignment: .top) {
                // Left export/share
                Button(action: { exportJournal() }) {
                    Image(systemName: "square.and.arrow.down")
                }
                Spacer()
                // Right-side actions, wrap to second line on narrow widths
                if geo.size.width < 380 {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 16) {
                            Button(action: { 
                                isTextModeActive.toggle()
                            }) {
                                Image(systemName: "character.cursor.ibeam")
                                    .foregroundColor(isTextModeActive ? .blue : .primary)
                            }
                            Button(action: { showToolPicker.toggle() }) {
                                Image(systemName: "applepencil.and.scribble")
                            }
                        }
                        HStack(spacing: 16) {
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
                } else {
                    HStack(spacing: 16) {
                        Button(action: { 
                            isTextModeActive.toggle()
                        }) {
                            Image(systemName: "character.cursor.ibeam")
                                .foregroundColor(isTextModeActive ? .blue : .primary)
                        }
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
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 60)
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
            
            // Text elements overlay
            ForEach(textElements.indices, id: \.self) { idx in
                DraggableTextView(text: $textElements[idx]) {
                    textElements.remove(at: idx)
                }
            }
            
            // Text input overlay when text mode is active
            if isTextModeActive {
                TextInputOverlay { text in
                    addTextElement(text: text)
                    isTextModeActive = false
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
        textElements.removeAll()
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
        saveTextElements()
    }
    
    // MARK: - Text Data Persistence
    private struct TextMeta: Codable {
        let id: String
        let text: String
        let x: Double
        let y: Double
        let fontSize: Double
        let color: String
    }
    
    private func textMetadataURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date) + "_texts.json"
        return photosDirectory().appendingPathComponent(name)
    }
    
    private func saveTextElements(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        guard !textElements.isEmpty else {
            try? FileManager.default.removeItem(at: textMetadataURL(for: targetDate))
            return
        }
        var metas: [TextMeta] = []
        for textElement in textElements {
            let id = textElement.id.uuidString
            let colorString = textElement.color.description
            metas.append(TextMeta(id: id, text: textElement.text, x: textElement.position.x, y: textElement.position.y, fontSize: textElement.fontSize, color: colorString))
        }
        if let jsonData = try? JSONEncoder().encode(metas) {
            try? jsonData.write(to: textMetadataURL(for: targetDate), options: .atomic)
        }
    }
    
    private func loadTextElements(for date: Date? = nil) {
        let targetDate = date ?? currentDate
        textElements.removeAll()
        let url = textMetadataURL(for: targetDate)
        guard let data = try? Data(contentsOf: url), let metas = try? JSONDecoder().decode([TextMeta].self, from: data) else { return }
        for meta in metas {
            let textElement = JournalText(
                id: UUID(uuidString: meta.id) ?? UUID(),
                text: meta.text,
                position: CGPoint(x: meta.x, y: meta.y),
                fontSize: meta.fontSize,
                color: Color(hex: meta.color) ?? .black
            )
            textElements.append(textElement)
        }
    }
    
    private func addTextElement(text: String) {
        let position = CGPoint(x: 150, y: 150) // Default position
        let newText = JournalText(
            id: UUID(),
            text: text,
            position: position,
            fontSize: 16,
            color: .black
        )
        textElements.append(newText)
        saveTextElements()
    }
    
    // MARK: - Photo model & view
    struct JournalPhoto: Identifiable {
        let id: UUID
        var image: UIImage
        var position: CGPoint
        var size: CGSize
        var rotation: Angle
    }
    
    struct JournalText: Identifiable {
        let id: UUID
        var text: String
        var position: CGPoint
        var fontSize: CGFloat
        var color: Color
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
    
    struct DraggableTextView: View {
        @Binding var text: JournalText
        var onDelete: () -> Void
        
        @State private var dragOffset: CGSize = .zero
        @State private var showDelete: Bool = false
        @State private var isEditing: Bool = false
        @State private var editingText: String = ""
        
        var body: some View {
            ZStack(alignment: .topLeading) {
                if isEditing {
                    TextField("Enter text", text: $editingText)
                        .font(.system(size: text.fontSize))
                        .foregroundColor(text.color)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            text.text = editingText
                            isEditing = false
                        }
                        .onAppear {
                            editingText = text.text
                        }
                } else {
                    Text(text.text)
                        .font(.system(size: text.fontSize))
                        .foregroundColor(text.color)
                        .padding(4)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(4)
                }
                
                if showDelete && !isEditing {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .offset(x: -10, y: -10)
                }
            }
            .position(x: text.position.x + dragOffset.width, y: text.position.y + dragOffset.height)
            .gesture(dragGesture)
            .onTapGesture {
                if !isEditing {
                    withAnimation { showDelete.toggle() }
                }
            }
            .onLongPressGesture {
                isEditing = true
                showDelete = false
            }
        }
        
        private var dragGesture: some Gesture {
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    text.position.x += value.translation.width
                    text.position.y += value.translation.height
                    dragOffset = .zero
                }
        }
    }
    
    struct TextInputOverlay: View {
        var onTextAdded: (String) -> Void
        
        @State private var inputText: String = ""
        @FocusState private var isTextFieldFocused: Bool
        
        var body: some View {
            VStack {
                Spacer()
                HStack {
                    TextField("Enter text", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            if !inputText.isEmpty {
                                onTextAdded(inputText)
                                inputText = ""
                            }
                        }
                    
                    Button("Add") {
                        if !inputText.isEmpty {
                            onTextAdded(inputText)
                            inputText = ""
                        }
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(10)
                .padding()
            }
            .onAppear {
                isTextFieldFocused = true
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
