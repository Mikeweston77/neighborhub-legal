import SwiftUI
import WebKit

/// A card displaying a link to the Waterfall 3 website with a visual preview
struct WebsiteLinkCard: View {
    let url: String = "https://waterfall3.co.za"
    let title: String = "Waterfall 3"
    let description: String = ""
    let iconName: String = "house"
    
    @State private var showingWebView = false
    @State private var showingOpenOptions = false
    @AppStorage("websiteLinkOpenPreference") private var openPreference: String = "ask" // "ask", "in-app", "safari"
    
    var body: some View {
        Button(action: {
            handleOpenWebsite()
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text("waterfall3.co.za")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(6)
            .frame(height: 130)
            .background(
                ZStack {
                    Image("waterfall3-bg 1")
                        .resizable()
                        .scaledToFill()
                        .opacity(1.95)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    // Overlay gradient for readability
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.25, blue: 0.45).opacity(0.7),
                            Color(red: 0.10, green: 0.45, blue: 0.65).opacity(0.5),
                            Color(red: 0.20, green: 0.60, blue: 0.50).opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // Subtle shimmer overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear,
                            Color.black.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 2)
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    if showingOpenOptions {
                        showingOpenOptions = false
                    }
                }
        )
        .confirmationDialog("Open Website", isPresented: $showingOpenOptions, titleVisibility: .visible) {
            Button("Open In-App") {
                openInApp()
            }
            Button("Open in Safari") {
                openInSafari()
            }
            Button("Always Open In-App") {
                openPreference = "in-app"
                openInApp()
            }
            Button("Always Open in Safari") {
                openPreference = "safari"
                openInSafari()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how to open waterfall3.co.za")
        }
        .fullScreenCover(isPresented: $showingWebView) {
            WebsiteWebPortalView(urlString: url, title: title)
        }
    }
    
    private func handleOpenWebsite() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        switch openPreference {
        case "in-app":
            openInApp()
        case "safari":
            openInSafari()
        default:
            showingOpenOptions = true
        }
    }
    
    private func openInApp() {
        showingWebView = true
    }
    
    private func openInSafari() {
        if let websiteURL = URL(string: url) {
            UIApplication.shared.open(websiteURL)
        }
    }
}

// MARK: - Website Web Portal View
struct WebsiteWebPortalView: View {
    let urlString: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var webViewModel = WebsiteWebViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                WebsiteViewContainer(
                    url: URL(string: urlString)!,
                    viewModel: webViewModel
                )
                
                if webViewModel.isLoading {
                    Color.black.opacity(0.05).ignoresSafeArea()
                    ProgressView("Loading...")
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                        )
                        .shadow(radius: 8)
                }
                
                if let error = webViewModel.error {
                    Color.black.opacity(0.05).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to load page")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            webViewModel.reload()
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                    .shadow(radius: 8)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Website Web View Model
class WebsiteWebViewModel: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var error: String? = nil
    fileprivate var webView: WKWebView?
    private var url: URL?
    
    func setWebView(_ webView: WKWebView, url: URL) {
        self.webView = webView
        self.url = url
    }
    
    func reload() {
        guard let webView = webView, let url = url else { return }
        error = nil
        isLoading = true
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Website View Container
struct WebsiteViewContainer: UIViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: WebsiteWebViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Enable mobile optimizations
        let preferences = WKWebpagePreferences()
        if #available(iOS 14.0, *) {
            preferences.allowsContentJavaScript = true
        }
        config.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.isScrollEnabled = true
        
        // Respect system appearance (light/dark mode)
        if #available(iOS 13.0, *) {
            webView.underPageBackgroundColor = .systemBackground
        }
        
        // Mobile-optimized user agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        viewModel.setWebView(webView, url: url)
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: WebsiteWebViewModel
        
        init(viewModel: WebsiteWebViewModel) {
            self.viewModel = viewModel
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
                self.viewModel.error = nil
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
            }
            
            // Inject viewport meta tag and mobile optimizations
            let mobileOptimizationScript = """
                (function() {
                    // Add viewport meta tag if missing
                    var viewport = document.querySelector('meta[name="viewport"]');
                    if (!viewport) {
                        viewport = document.createElement('meta');
                        viewport.name = 'viewport';
                        viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
                        document.head.appendChild(viewport);
                    }
                    
                    // Force responsive layout
                    document.body.style.maxWidth = '100vw';
                    document.body.style.overflowX = 'hidden';
                    
                    // Add mobile-friendly touch target sizes
                    var style = document.createElement('style');
                    style.textContent = `
                        * { -webkit-tap-highlight-color: rgba(0,0,0,0.1); }
                        a, button { min-height: 44px; min-width: 44px; }
                    `;
                    document.head.appendChild(style);
                })();
            """
            webView.evaluateJavaScript(mobileOptimizationScript, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.error = error.localizedDescription
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview
struct WebsiteLinkCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            WebsiteLinkCard()
            
            WebsiteLinkCard()
                .preferredColorScheme(.dark)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}
