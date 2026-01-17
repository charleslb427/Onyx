
import SwiftUI
import WebKit
import UserNotifications

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID
    
    // SINGLETON PROCESS POOL (Critical for Session Persistence)
    static let sharedPool = WKProcessPool()
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        
        // PERSISTENCE: Link to shared pool + default store
        config.processPool = WebViewWrapper.sharedPool
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // --- 1. CSS GENERATOR (Dynamic) ---
        let css = generateCSS()
        
        // --- 2. INJECT CSS AT DOCUMENT START (Fix Flash/Start Bug) ---
        // This ensures filtering happens BEFORE rendering
        let cssScript = """
        var s = document.createElement('style');
        s.id = 'onyx-style';
        s.textContent = `\(css)`;
        document.documentElement.appendChild(s);
        """
        let userScriptCSS = WKUserScript(source: cssScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScriptCSS)
        
        // --- 3. NOTIFICATION BRIDGE ---
        let notificationShimScript = """
        window.Notification = function(title, options) {
            var payload = { title: title, body: options ? (options.body || '') : '', tag: options ? (options.tag || '') : '' };
            window.webkit.messageHandlers.notificationBridge.postMessage(payload);
            this.close = function() {};
        };
        window.Notification.permission = 'granted';
        window.Notification.requestPermission = function(cb) { if(cb) cb('granted'); return Promise.resolve('granted'); };
        """
        let userScriptNotif = WKUserScript(source: notificationShimScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScriptNotif)
        config.userContentController.add(context.coordinator, name: "notificationBridge")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // --- 4. RE-ENABLE SWIPE (Using Policy to fix bugs) ---
        webView.allowsBackForwardNavigationGestures = true
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webView = webView
        
        loadRequest(for: webView)
        return webView
    }
    
    // Helper to generate CSS string based on current settings
    func generateCSS() -> String {
        let defaults = UserDefaults.standard
        let hideReels = defaults.bool(forKey: "hideReels")
        let hideExplore = defaults.bool(forKey: "hideExplore")
        let hideAds = defaults.bool(forKey: "hideAds")
        
        var css = ""
        // Force Hide (Aggressive)
        if hideReels {
            css += "a[href*='/reels/'], div[style*='reels'], svg[aria-label*='Reels'], a[href='/reels/'] { display: none !important; } div:has(> a[href*='/reels/']) { display: none !important; } "
        }
        if hideExplore {
            css += "a[href='/explore/'], a[href*='/explore'] { display: none !important; } div:has(> a[href*='/explore/']) { display: none !important; } "
        }
        if hideAds {
            css += "article:has(span[class*='sponsored']), article:has(span:contains('Sponsorisé')), article:has(span:contains('Sponsored')) { display: none !important; } "
        }
        
        // UI Cleanup
        css += "div[role='tablist'], div:has(> a[href='/']) { justify-content: space-evenly !important; } div[role='banner'] { display: none !important; } footer { display: none !important; } .AppCTA { display: none !important; }"
        
        return css
    }

    func loadRequest(for webView: WKWebView) {
        if let url = URL(string: "https://www.instagram.com/") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    // When Settings Close -> Update CSS immediately without full reload if possible, or reload
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRefreshId != refreshTrigger {
            context.coordinator.lastRefreshId = refreshTrigger
            
            // Update CSS dynamically
            let newCSS = generateCSS()
            let js = """
            var s = document.getElementById('onyx-style');
            if (s) { s.textContent = `\(newCSS)`; }
            else {
                s = document.createElement('style'); s.id = 'onyx-style'; s.textContent = `\(newCSS)`; document.documentElement.appendChild(s);
            }
            """
            uiView.evaluateJavaScript(js, completionHandler: nil)
            uiView.reload()
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebViewWrapper
        weak var webView: WKWebView?
        var lastRefreshId: UUID = UUID()
        
        init(_ parent: WebViewWrapper) { self.parent = parent }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "notificationBridge", let body = message.body as? [String: Any], let title = body["title"] as? String {
                let text = body["body"] as? String ?? ""
                dispatchLocalNotification(title: title, body: text)
            }
        }
        
        func dispatchLocalNotification(title: String, body: String) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        @objc func handleRefresh() { webView?.reload() }

        // --- NAVIGATION POLICY (The Anti-White Screen Fix) ---
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url?.absoluteString else {
                decisionHandler(.allow)
                return
            }
            
            let defaults = UserDefaults.standard
            
            // If Reels Hidden AND User tries to navigate to Reels (Click or Swipe Back) -> CANCEL
            if defaults.bool(forKey: "hideReels") && url.contains("/reels/") {
                print("⛔ Blocked navigation to Reels")
                decisionHandler(.cancel)
                return
            }
            
            // If Explore Hidden -> CANCEL
            if defaults.bool(forKey: "hideExplore") && url.contains("/explore/") {
                print("⛔ Blocked navigation to Explore")
                decisionHandler(.cancel)
                return
            }
            
            // Allow everything else
            decisionHandler(.allow)
        }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.grant) }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(.allow) }
    }
}
