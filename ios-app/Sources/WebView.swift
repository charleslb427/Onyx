
import SwiftUI
import WebKit
import UserNotifications

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        
        // PERSISTENCE: Explicitly use default persistent store
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // --- NOTIFICATION BRIDGE ---
        let notificationShimScript = """
        window.Notification = function(title, options) {
            var payload = { title: title, body: options ? (options.body || '') : '', tag: options ? (options.tag || '') : '' };
            window.webkit.messageHandlers.notificationBridge.postMessage(payload);
            this.close = function() {};
        };
        window.Notification.permission = 'granted';
        window.Notification.requestPermission = function(cb) { if(cb) cb('granted'); return Promise.resolve('granted'); };
        """
        let userScript = WKUserScript(source: notificationShimScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "notificationBridge")
        // ---------------------------
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // DISABLE BROWSER SWIPE TO FIX BUGS
        webView.allowsBackForwardNavigationGestures = false 
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webView = webView
        
        loadRequest(for: webView)

        return webView
    }

    func loadRequest(for webView: WKWebView) {
        if let url = URL(string: "https://www.instagram.com/") {
            // Use default cache policy (protocol compliant) to avoid stale login pages
            // .returnCacheDataElseLoad can be too aggressive for auth tokens
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRefreshId != refreshTrigger {
            context.coordinator.lastRefreshId = refreshTrigger
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            injectFilters(webView)
        }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.grant) }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(.allow) }

        func injectFilters(_ webView: WKWebView) {
            let defaults = UserDefaults.standard
            let hideReels = defaults.bool(forKey: "hideReels")
            let hideExplore = defaults.bool(forKey: "hideExplore")
            let hideAds = defaults.bool(forKey: "hideAds")
            
            var css = ""
            if hideReels { css += "a[href*='/reels/'], div[style*='reels'], svg[aria-label*='Reels'], a[href='/reels/'] { display: none !important; } div:has(> a[href*='/reels/']) { display: none !important; } " }
            if hideExplore { css += "a[href='/explore/'], a[href*='/explore'] { display: none !important; } div:has(> a[href*='/explore/']) { display: none !important; } " }
            if hideAds { css += "article:has(span[class*='sponsored']), article:has(span:contains('Sponsorisé')), article:has(span:contains('Sponsored')) { display: none !important; } " }
            
            css += "div[role='tablist'], div:has(> a[href='/']) { justify-content: space-evenly !important; } div[role='banner'] { display: none !important; } div:has(button:contains('Ouvrir in App')) { display: none !important; } footer { display: none !important; }"
            
            let js = "var s=document.createElement('style');s.id='onyx-style';s.textContent=\"\(css)\";document.head.appendChild(s);"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
