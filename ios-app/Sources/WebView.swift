
import SwiftUI
import WebKit
import UserNotifications

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        
        // --- 1. SETUP NOTIFICATION BRIDGE (THE NINJA TRICK) ---
        let notificationShimScript = """
        // Override standard Notification API
        window.Notification = function(title, options) {
            // 1. Capture payload
            var payload = {
                title: title,
                body: options ? (options.body || '') : '',
                tag: options ? (options.tag || '') : ''
            };
            
            // 2. Send to Swift
            window.webkit.messageHandlers.notificationBridge.postMessage(payload);
            
            // 3. Mock standard properties
            this.close = function() {};
        };
        
        // Mock permission status so Instagram thinks it can send notifications
        window.Notification.permission = 'granted';
        window.Notification.requestPermission = function(cb) {
            var p = 'granted';
            if (cb) { cb(p); }
            return Promise.resolve(p);
        };
        
        // Also mock ServiceWorker registration for push (generic)
        navigator.serviceWorker.getRegistration().then(function(reg) {
            if (reg && reg.pushManager) {
                // Hook into push manager if needed, mainly Notification API is enough for foreground/active tab
            }
        });
        """
        
        let userScript = WKUserScript(source: notificationShimScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        
        // Register the bridge handler
        config.userContentController.add(context.coordinator, name: "notificationBridge")
        // ------------------------------------------------------
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Refresh Control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        // User Agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

        context.coordinator.webView = webView
        
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRefreshId != refreshTrigger {
            context.coordinator.lastRefreshId = refreshTrigger
            uiView.reload()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Coordinator acts as the Bridge Delegate
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebViewWrapper
        weak var webView: WKWebView?
        var lastRefreshId: UUID = UUID()
        
        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }
        
        // --- HANDLE MESSAGES FROM JS (THE NINJA RECEIVER) ---
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "notificationBridge",
               let body = message.body as? [String: Any],
               let title = body["title"] as? String {
                
                let text = body["body"] as? String ?? ""
                dispatchLocalNotification(title: title, body: text)
            }
        }
        
        func dispatchLocalNotification(title: String, body: String) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            
            // Set Badge +1
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

            // Trigger immediately (or very short delay)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error bridging notification: \(error)")
                }
            }
        }
        // ----------------------------------------------------

        @objc func handleRefresh() {
            webView?.reload()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            injectFilters(webView)
            
            // Important: Force Instagram to check permissions again if needed
            let checkJS = """
            if (Notification.permission !== 'granted') {
                Notification.permission = 'granted';
            }
            """
            webView.evaluateJavaScript(checkJS, completionHandler: nil)
        }
        
        // Permissions
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
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
                css += "a[href*='/reels/'], div[style*='reels'], svg[aria-label*='Reels'], a[href='/reels/'] { display: none !important; } div:has(> a[href*='/reels/']) { display: none !important; } "
            }
            if hideExplore {
                css += "a[href='/explore/'], a[href*='/explore'] { display: none !important; } div:has(> a[href*='/explore/']) { display: none !important; } "
            }
            if hideAds {
                css += "article:has(span[class*='sponsored']), article:has(span:contains('Sponsorisé')), article:has(span:contains('Sponsored')) { display: none !important; } "
            }
            
            css += "div[role='tablist'], div:has(> a[href='/']) { justify-content: space-evenly !important; } div[role='banner'] { display: none !important; } div:has(button:contains('Ouvrir in App')) { display: none !important; }"
            
            let js = """
            var s = document.createElement('style');
            s.id = 'onyx-style';
            s.textContent = "\(css)";
            document.head.appendChild(s);
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
