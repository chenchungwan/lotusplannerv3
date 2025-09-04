import SwiftUI
import PencilKit
import PhotosUI

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
    // @StateObject private var firestoreManager = FirestoreManager.shared // Removed - using local storage only
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
    @State private var isUsingEraser = false
    @State private var containerSize: CGSize = .zero
    
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
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
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
            
            // Saved scrapbook entries for today - TEMPORARILY DISABLED
            // TODO: Implement local scrapbook entry storage
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
                ZStack(alignment: .topTrailing) {
                    // PencilKit Canvas (background layer)
                    ScrapbookPencilKitView(canvasView: $canvasView)
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
                    
                    // Top-right inline controls (row)
                    HStack(spacing: 8) {
                        // Toggle Pen tool
                        Button(action: {
                            isUsingEraser = false
                            canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)
                        }) {
                            Image(systemName: "pencil")
                                .padding(10)
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                        }

                        // Toggle Eraser tool
                        Button(action: {
                            isUsingEraser = true
                            canvasView.tool = PKEraserTool(.vector)
                        }) {
                            Image(systemName: "eraser")
                                .padding(10)
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                        }

                        // Add Photo
                        Button(action: { isShowingPhotoPicker = true }) {
                            Image(systemName: "photo.on.rectangle")
                                .padding(10)
                                .background(Color(.systemBackground).opacity(0.8))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 8)

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

// MARK: - PencilKit View (unchanged)
struct ScrapbookPencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.backgroundColor = UIColor.clear
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update the view if needed
    }
}

#Preview {
    ScrapbookComponent(canvasView: .constant(PKCanvasView()))
        .frame(height: 400)
}
