import SwiftUI
import PencilKit
import PhotosUI

// MARK: - Drawing Tool Models
enum DrawingTool: String, CaseIterable {
    case pen = "pencil"
    case marker = "paintbrush.pointed"
    case pencil = "pencil.tip"
    case eraser = "eraser"
    case monoline = "pencil.line"
    
    var pkTool: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .marker: return .marker
        case .pencil: return .pencil
        case .eraser: return .pen // Will be handled differently
        case .monoline: return .monoline
        }
    }
    
    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .pencil: return "Pencil"
        case .eraser: return "Eraser"
        case .monoline: return "Monoline"
        }
    }
    
    var description: String {
        switch self {
        case .pen: return "Pressure-sensitive pen"
        case .marker: return "Highlighter style"
        case .pencil: return "Textured pencil"
        case .eraser: return "Remove drawings"
        case .monoline: return "Consistent width"
        }
    }
}

// MARK: - Photo Model
struct ScrapbookPhoto: Identifiable, Codable {
    let id = UUID()
    var imageData: Data
    var position: CGPoint
    var size: CGSize
    var rotation: Double
    var zIndex: Int
    
    init(imageData: Data, position: CGPoint = CGPoint(x: 100, y: 100), size: CGSize = CGSize(width: 150, height: 150)) {
        self.imageData = imageData
        self.position = position
        self.size = size
        self.rotation = 0
        self.zIndex = 0
    }
}

// MARK: - Draggable Photo View
struct DraggablePhotoView: View {
    @Binding var photo: ScrapbookPhoto
    @Binding var selectedPhotoId: UUID?
    let containerSize: CGSize
    let onDelete: () -> Void
    
    @State private var dragOffset = CGSize.zero
    @State private var lastRotation: Double = 0
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    
    private var isSelected: Bool {
        selectedPhotoId == photo.id
    }
    
    var body: some View {
        Group {
            if let uiImage = UIImage(data: photo.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photo.size.width * finalScale, height: photo.size.height * finalScale)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .overlay(
                        // Delete button when selected
                        Group {
                            if isSelected {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: onDelete) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(4)
                            }
                        }
                    )
                    .scaleEffect(currentScale)
                    .rotationEffect(.degrees(photo.rotation))
                    .position(
                        x: photo.position.x + dragOffset.width,
                        y: photo.position.y + dragOffset.height
                    )
                    .gesture(
                        SimultaneousGesture(
                            // Drag gesture
                            DragGesture()
                                .onChanged { value in
                                    selectedPhotoId = photo.id
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Update position within bounds
                                    let newX = max(photo.size.width/2, min(containerSize.width - photo.size.width/2, photo.position.x + value.translation.width))
                                    let newY = max(photo.size.height/2, min(containerSize.height - photo.size.height/2, photo.position.y + value.translation.height))
                                    
                                    photo.position = CGPoint(x: newX, y: newY)
                                    dragOffset = .zero
                                },
                            
                            // Combined scale and rotation gesture
                            MagnificationGesture()
                                .simultaneously(with: RotationGesture())
                                .onChanged { value in
                                    selectedPhotoId = photo.id
                                    currentScale = value.first?.magnitude ?? 1.0
                                    
                                    if let rotationValue = value.second {
                                        photo.rotation = lastRotation + rotationValue.degrees
                                    }
                                }
                                .onEnded { value in
                                    if let scaleValue = value.first {
                                        finalScale *= scaleValue.magnitude
                                        finalScale = max(0.5, min(3.0, finalScale)) // Limit scale
                                        
                                        // Update photo size
                                        photo.size = CGSize(
                                            width: photo.size.width * scaleValue.magnitude,
                                            height: photo.size.height * scaleValue.magnitude
                                        )
                                    }
                                    
                                    currentScale = 1.0
                                    lastRotation = photo.rotation
                                }
                        )
                    )
                    .onTapGesture {
                        selectedPhotoId = selectedPhotoId == photo.id ? nil : photo.id
                    }
            }
        }
    }
}

// MARK: - Enhanced Scrapbook Component
struct ScrapbookComponent: View {
    @Binding var canvasView: PKCanvasView
    // Note: Scrapbook storage functionality temporarily disabled
    @State private var showingSaveAlert = false
    @State private var scrapbookTitle = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    let title: String
    let currentDate: Date
    let accountKind: GoogleAuthManager.AccountKind
    
    @State private var photos: [ScrapbookPhoto] = []
    @State private var selectedPhotoId: UUID?
    @State private var isShowingPhotoPicker = false
    @State private var containerSize: CGSize = .zero
    
    // Drawing tool states
    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .black
    @State private var penWidth: CGFloat = 2.0
    @State private var showingColorPicker = false
    @State private var showingToolPalette = false
    
    init(canvasView: Binding<PKCanvasView>, title: String = "Journal", currentDate: Date = Date(), accountKind: GoogleAuthManager.AccountKind = .personal) {
        self._canvasView = canvasView
        self.title = title
        self.currentDate = currentDate
        self.accountKind = accountKind
    }
    
    // MARK: - Helper Methods
    private func binding(for photo: ScrapbookPhoto) -> Binding<ScrapbookPhoto> {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else {
            fatalError("Photo not found")
        }
        return $photos[index]
    }
    
    private func addPhoto(imageData: Data) {
        let newPhoto = ScrapbookPhoto(
            imageData: imageData,
            position: CGPoint(x: containerSize.width/2, y: containerSize.height/2),
            size: CGSize(width: 150, height: 150)
        )
        photos.append(newPhoto)
        selectedPhotoId = newPhoto.id
    }
    
    private func deletePhoto(_ photo: ScrapbookPhoto) {
        photos.removeAll { $0.id == photo.id }
        if selectedPhotoId == photo.id {
            selectedPhotoId = nil
        }
    }
    
    // MARK: - Firestore Integration Methods
    private func scrapbookEntryCard(_ entry: ScrapbookEntry) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray4))
                .frame(width: 50, height: 40)
                .overlay(
                    Image(systemName: "doc.richtext")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
            
            Text(entry.title ?? "Untitled")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 50)
        }
        .onTapGesture {
            // TODO: Open PDF viewer to display the saved scrapbook entry
            print("Tapped scrapbook entry: \(entry.title ?? "Untitled")")
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleteScrapbookEntry(entry)
            }
        }
    }
    
    private func saveScrapbook() {
        // TEMPORARILY DISABLED - Scrapbook saving is suspended
        print("📖 Scrapbook saving temporarily disabled")
        errorMessage = "Scrapbook saving is temporarily disabled"
        scrapbookTitle = ""
    }
    
    private func loadScrapbookEntries() {
        // TEMPORARILY DISABLED - Scrapbook loading is suspended
        print("📖 Scrapbook loading temporarily disabled")
    }
    
    private func deleteScrapbookEntry(_ entry: ScrapbookEntry) {
        // TEMPORARILY DISABLED - Scrapbook deletion is suspended
        print("📖 Scrapbook deletion temporarily disabled")
        errorMessage = "Scrapbook deletion is temporarily disabled"
    }
    
    // MARK: - Drawing Tools Palette
    private var drawingToolsPalette: some View {
        VStack(spacing: 8) {
            // Tool Selection Row
            HStack(spacing: 12) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button(action: {
                        selectedTool = tool
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tool.rawValue)
                                .font(.title2)
                                .foregroundColor(selectedTool == tool ? .white : .primary)
                            
                            Text(tool.displayName)
                                .font(.caption2)
                                .foregroundColor(selectedTool == tool ? .white : .secondary)
                        }
                        .frame(width: 60, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTool == tool ? Color.blue : Color(.systemGray6))
                        )
                    }
                }
                
                Spacer()
                
                // Quick Color Picker
                Button(action: {
                    showingColorPicker = true
                }) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: 2)
                        )
                }
            }
            .padding(.horizontal)
            
            // Tool Options (when not eraser)
            if selectedTool != .eraser {
                VStack(spacing: 8) {
                    // Pen Width Slider
                    HStack {
                        Text("Width:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $penWidth, in: 1...20, step: 1)
                            .frame(width: 100)
                        
                        Text("\(Int(penWidth))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 25)
                    }
                    
                    // Color Palette
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(predefinedColors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 25, height: 25)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPicker("Choose Color", selection: $selectedColor)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // Predefined color palette
    private var predefinedColors: [Color] {
        [
            .black, .gray, .red, .orange,
            .yellow, .green, .blue, .purple,
            .pink, .brown, .indigo, .cyan,
            .mint, .teal, .white, Color(.systemGray4)
        ]
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Drawing Tools Toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingToolPalette.toggle()
                        }
                    }) {
                        Image(systemName: showingToolPalette ? "paintpalette.fill" : "paintpalette")
                            .font(.caption)
                            .foregroundColor(showingToolPalette ? .blue : .primary)
                    }
                    
                    // Save to Firestore button
                    Button(action: {
                        showingSaveAlert = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .disabled(canvasView.drawing.strokes.isEmpty && photos.isEmpty)
                    
                    // Add Photo Button
                    Button(action: {
                        isShowingPhotoPicker = true
                    }) {
                        Image(systemName: "photo.badge.plus")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    // Clear Drawing Button
                    Button("Clear Drawing") {
                        canvasView.drawing = PKDrawing()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    // Clear All Button
                    Button("Clear All") {
                        canvasView.drawing = PKDrawing()
                        photos.removeAll()
                        selectedPhotoId = nil
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Drawing Tools Palette (conditionally shown)
            if showingToolPalette {
                drawingToolsPalette
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            
            // Saved scrapbook entries for today
            // Note: Scrapbook entry display temporarily disabled
            /*
            if !scrapbookEntries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(scrapbookEntries) { entry in
                            scrapbookEntryCard(entry)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 60)
            }
            */
            
            // Main Scrapbook Area
            GeometryReader { geometry in
                ZStack {
                    // PencilKit Canvas (background layer)
                    ScrapbookPencilKitView(
                        canvasView: $canvasView,
                        selectedTool: selectedTool,
                        selectedColor: selectedColor,
                        penWidth: penWidth
                    )
                    .background(Color(.systemBackground))
                        .onTapGesture {
                            // Deselect photo when tapping empty area
                            selectedPhotoId = nil
                        }
                    
                    // Photos layer
                    ForEach(photos.sorted(by: { $0.zIndex < $1.zIndex })) { photo in
                        DraggablePhotoView(
                            photo: binding(for: photo),
                            selectedPhotoId: $selectedPhotoId,
                            containerSize: geometry.size,
                            onDelete: {
                                deletePhoto(photo)
                            }
                        )
                    }
                    
                    // Loading overlay
                    if isSaving {
                        Color.black.opacity(0.3)
                            .overlay(
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Saving to Firestore...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.top, 8)
                                }
                                .padding()
                                .background(Color(.systemBackground).opacity(0.9))
                                .cornerRadius(12)
                            )
                    }
                }
                .onAppear {
                    containerSize = geometry.size
                }
                .onChange(of: geometry.size) { newSize in
                    containerSize = newSize
                }
            }
            .cornerRadius(8)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.tertiarySystemBackground))
        .sheet(isPresented: $isShowingPhotoPicker) {
            PhotoPicker { imageData in
                addPhoto(imageData: imageData)
            }
        }
        .alert("Save Scrapbook", isPresented: $showingSaveAlert) {
            TextField("Title (optional)", text: $scrapbookTitle)
            Button("Save") {
                saveScrapbook()
            }
            Button("Cancel", role: .cancel) {
                scrapbookTitle = ""
            }
        } message: {
            Text("Save your current drawing and photos as a PDF to your scrapbook?")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            loadScrapbookEntries()
        }
        .onChange(of: currentDate) { oldValue, newValue in
            loadScrapbookEntries()
        }
    }
}
// MARK: - Photo Picker
struct PhotoPicker: UIViewControllerRepresentable {
    let onImageSelected: (Data) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                if let uiImage = image as? UIImage,
                   let imageData = uiImage.jpegData(compressionQuality: 0.8) {
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(imageData)
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced PencilKit View
struct ScrapbookPencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let selectedTool: DrawingTool
    let selectedColor: Color
    let penWidth: CGFloat
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .pencilOnly // Prefer Apple Pencil for best experience
        canvasView.backgroundColor = UIColor.clear
        canvasView.allowsFingerDrawing = true // Allow finger drawing as backup
        updateTool()
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        updateTool()
    }
    
    private func updateTool() {
        if selectedTool == .eraser {
            canvasView.tool = PKEraserTool(.bitmap)
        } else {
            let uiColor = UIColor(selectedColor)
            canvasView.tool = PKInkingTool(selectedTool.pkTool, color: uiColor, width: penWidth)
        }
    }
}

#Preview {
    ScrapbookComponent(canvasView: .constant(PKCanvasView()))
        .frame(height: 400)
}
