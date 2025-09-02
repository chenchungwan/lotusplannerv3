import SwiftUI
import WebKit

struct ReportIssuesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    
    // Placeholder URL - will be replaced with actual Google Form URL later
    private let googleFormURL = "https://forms.google.com/placeholder-form-url"
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading report form...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Placeholder content until Google Form is integrated
                    VStack(spacing: 24) {
                        Spacer()
                        
                        // Icon
                        Image(systemName: "exclamationmark.bubble")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        // Title
                        Text("Report an Issue")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        // Description
                        VStack(spacing: 12) {
                            Text("Help us improve Lotus Planner by reporting bugs, suggesting features, or sharing feedback.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("The Google Form integration will be available soon.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer()
                        
                        // Placeholder button for future Google Form
                        Button(action: {
                            // TODO: Load Google Form in web view
                            loadGoogleForm()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "safari")
                                Text("Open Report Form")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .disabled(true) // Disabled until Google Form URL is configured
                        .opacity(0.6)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }
                
                // Future: WebView will go here
                // WebView(url: googleFormURL, isLoading: $isLoading)
            }
            .navigationTitle("Report Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func loadGoogleForm() {
        // TODO: Implement Google Form loading
        // This will be implemented when the actual Google Form URL is provided
        print("📝 Loading Google Form for issue reporting...")
        isLoading = true
        
        // Simulate loading for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
        }
    }
}

// MARK: - WebView (for future Google Form integration)
struct WebView: UIViewRepresentable {
    let url: String
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: url) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            print("❌ WebView failed to load: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ReportIssuesView()
}
