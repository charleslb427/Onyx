
import SwiftUI
import WebKit

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.applicationNameForUserAgent = "Onyx/1.0"
        
        // Optimize for mobile usage
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator // Handle Permission Popups (Camera/Mic)
        
        // ENABLE SWIPE NAVIGATION (Back/Forward)
        webView.allowsBackForwardNavigationGestures = true
        
        // ENABLE PULL-TO-REFRESH
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        // Setup User Agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 250.0.0.0.0"

        context.coordinator.webView = webView
        
        // Load initial URL
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If refreshTrigger changed, reload
        if context.coordinator.lastRefreshId != refreshTrigger {
            context.coordinator.lastRefreshId = refreshTrigger
            uiView.reload()
            // Re-inject updated CSS happen in didFinish
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewWrapper
        weak var webView: WKWebView?
        var lastRefreshId: UUID = UUID()
        
        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }
        
        @objc func handleRefresh() {
            webView?.reload()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            injectFilters(webView)
        }
        
        // Handle Permission Requests (Camera, Mic, and potentially others)
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
        // Handle generic device permissions (Geoloc, Notifications if wrapped correctly)
        // Note: For Push on iOS, 'com.apple.developer.aps-environment' entitlement is usually required.
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }

        func injectFilters(_ webView: WKWebView) {
            let defaults = UserDefaults.standard
            let hideReels = defaults.bool(forKey: "hideReels")
            let hideExplore = defaults.bool(forKey: "hideExplore")
            let hideAds = defaults.bool(forKey: "hideAds")
            
            var css = ""
            
            if hideReels {
                css += """
                a[href*='/reels/'], div[style*='reels'], svg[aria-label*='Reels'], a[href='/reels/'] { display: none !important; }
                div:has(> a[href*='/reels/']) { display: none !important; }
                """
            }
            
            if hideExplore {
                css += """
                a[href='/explore/'], a[href*='/explore'] { display: none !important; }
                div:has(> a[href*='/explore/']) { display: none !important; }
                """
            }
            
            if hideAds {
                css += """
                article:has(span[class*='sponsored']), article:has(span:contains('Sponsorisé')), article:has(span:contains('Sponsored')) { display: none !important; }
                """
            }
            
            // Common Anti-Nag & Layout Fixes
            css += """
            /* Re-layout Navigation Bar (Space Evenly) */
            div[role='tablist'], div:has(> a[href='/']) { justify-content: space-evenly !important; }

            /* NO NAGS */
            div[role='banner'], div:has(a[href*='play.google.com']), div:has(a[href*='apps.apple.com']) { display: none !important; }
            div:has(button:contains('Ouvrir')), div:has(button:contains('Open')), div:has(button:contains('Installer')) { display: none !important; }
            footer:has(a[href*='apps.apple.com']) { display: none !important; }
            """
            
            // Minify CSS slightly to avoid newlines breaking string injection
            css = css.replacingOccurrences(of: "\n", with: " ")
            
            let js = """
            var styleId = 'onyx-style';
            var existing = document.getElementById(styleId);
            if (existing) existing.remove();
            var style = document.createElement('style');
            style.id = styleId;
            style.textContent = "\(css)";
            document.head.appendChild(style);
            """
            
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
