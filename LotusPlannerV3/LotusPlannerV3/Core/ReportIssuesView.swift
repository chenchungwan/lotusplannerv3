import SwiftUI
import WebKit
import SafariServices

struct ReportIssuesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    
    // Google Form URL for reporting issues / requesting features
    private let googleFormURL = "https://forms.gle/S5SsKySD83rRqTcu7"
    
    var body: some View {
        NavigationStack {
            SafariView(urlString: googleFormURL)
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
    
    private func loadGoogleForm() {}
}

// MARK: - WebView (for future Google Form integration)
struct WebView: UIViewRepresentable {
    let url: String
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Use a mobile Safari user agent to avoid any desktop-specific blocks
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let target = URL(string: url) else { return }
        // Start loading indicator before request
        isLoading = true
        let request = URLRequest(url: target)
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
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
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - SafariView (recommended for external forms)
struct SafariView: UIViewControllerRepresentable {
    let urlString: String
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let url = URL(string: urlString) ?? URL(string: "https://forms.gle/S5SsKySD83rRqTcu7")!
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = .label
        vc.dismissButtonStyle = .done
        return vc
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    ReportIssuesView()
}
