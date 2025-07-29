import SwiftUI
import PDFKit
import PencilKit

struct JournalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentDate: Date
    @State private var canvasView = PKCanvasView()
    // Track previous date to save when date changes
    @State private var previousDate: Date

    /// When `embedded` is `true` the view shows only the canvas/background
    /// content and omits its own `NavigationStack` + toolbars so it can be
    /// embedded inside another navigation hierarchy without duplicating the
    /// nav bar.
    var embedded: Bool = false
    
    init(currentDate: Date, embedded: Bool = false) {
        _currentDate = State(initialValue: currentDate)
        _previousDate = State(initialValue: currentDate)
        self.embedded = embedded
    }
    
    // Interval is always day for journal navigation (reuse same step logic)
    private func step(_ direction: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: direction, to: currentDate) else { return }
        // Save drawing for current date before switching
        JournalManager.shared.saveDrawing(for: currentDate, drawing: canvasView.drawing)
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
                canvasContent
                    .onAppear { loadDrawing() }
            } else {
                NavigationStack {
                    canvasContent
                        .navigationTitle("")
                        .toolbarTitleDisplayMode(.inline)
                        .onAppear { loadDrawing() }
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
                                    dismiss()
                                }
                            }
                        }
                }
            }
        }
    }

    private var canvasContent: some View {
        ZStack {
            // PDF background
            if let url = JournalManager.shared.backgroundPDFURL,
               let doc = PDFDocument(url: url) {
                PDFKitView(document: doc)
                    .ignoresSafeArea()
            }

            // PencilKit canvas overlay
            PencilKitView(canvasView: $canvasView)
                .ignoresSafeArea()
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