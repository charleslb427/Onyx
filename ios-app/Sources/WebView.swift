
import SwiftUI
import WebKit
import UserNotifications

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        
        // ✅ PERSISTENCE
        config.processPool = AppDelegate.shared.webViewProcessPool
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // --- EARLY CSS INJECTION (Reduces flash when loading) ---
        let earlyHideScript = """
        (function() {
            var style = document.createElement('style');
            style.id = 'onyx-early-hide';
            style.textContent = 'a[href*="/reels/"], a[href="/reels/"], a[href="/explore/"], a[href*="/explore"], div[role="banner"], footer { opacity: 0 !important; transition: opacity 0.1s; }';
            document.documentElement.appendChild(style);
        })();
        """
        let earlyHideUserScript = WKUserScript(source: earlyHideScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(earlyHideUserScript)
        
        // --- NOTIFICATION BRIDGE ---
        let notificationShimScript = """
        window.Notification = function(title, options) {
            var payload = { title: title, body: options ? (options.body || '') : '' };
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
        // ✅ START DISABLED - will be enabled dynamically when there's history
        webView.allowsBackForwardNavigationGestures = false
        
        // Pull to Refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webView = webView
        
        // ✅ RESTORE SESSION THEN LOAD
        SessionManager.shared.restoreSession(to: webView) {
            if let url = URL(string: "https://www.instagram.com/") {
                webView.load(URLRequest(url: url))
            }
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRefreshId != refreshTrigger {
            context.coordinator.lastRefreshId = refreshTrigger
            uiView.reload()
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastRefreshId: UUID = UUID()
        var hasInjectedLocalStorage = false
        
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
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        @objc func handleRefresh() {
            webView?.reload()
        }

        // --- NAVIGATION DELEGATE ---
        
        // ✅ INJECT LOCALSTORAGE + FILTERS EARLY (before page fully renders)
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if !hasInjectedLocalStorage {
                SessionManager.shared.injectLocalStorage(to: webView)
                hasInjectedLocalStorage = true
            }
            // Inject filters early to reduce flash
            injectFilters(into: webView)
        }
        
        // ✅ DYNAMIC SWIPE & NAV LOGIC
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            let defaults = UserDefaults.standard
            
            // 1. BLOCK BLANK/EMPTY
            if urlString == "about:blank" || urlString.isEmpty {
                decisionHandler(.cancel)
                return
            }
            
            // 2. BLOCK REELS FEED (Infinite Scroll) but ALLOW specific Reels (DMs/Saved)
            // The main feed is usually /reels/ or /reels/audio/...
            // Specific reels are /reels/C7k... (ID)
            // Strategy: Block strict /reels/ URL, but rely on CSS to remove the button.
            // If user somehow gets to the main feed, we block it.
            if defaults.bool(forKey: "hideReels") {
                // Block ONLY the main feed entry point, allow ids (longer urls)
                // "https://www.instagram.com/reels/" -> exact match or with query params
                if urlString == "https://www.instagram.com/reels/" || urlString.contains("/reels/audio/") {
                     decisionHandler(.cancel)
                     return
                }
            }

            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            injectFilters(into: webView)
            
            // ✅ SMART SWIPE CONTROL
            // Fix White Screen: Strictly disable swipe BACK if we are on Home
            if let url = webView.url?.absoluteString, url == "https://www.instagram.com/" {
                webView.allowsBackForwardNavigationGestures = false
            } else {
                // Otherwise only enable if valid history exists
                webView.allowsBackForwardNavigationGestures = webView.canGoBack
            }
            
            SessionManager.shared.saveSession(from: webView)
        }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func injectFilters(into webView: WKWebView) {
            let defaults = UserDefaults.standard
            let hideReels = defaults.bool(forKey: "hideReels")
            let hideExplore = defaults.bool(forKey: "hideExplore")
            let hideAds = defaults.bool(forKey: "hideAds")
            
            var css = ""
            
            if hideReels {
                // 1. Hide Reels Tab Button
                css += "a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; } "
                
                // 2. Hide "Reels" section in Profile
                css += "a[href*='/reels/'] { display: none !important; } " 
                
                // 3. Try to disable scroll on Reel pages (Anti-Doomscroll)
                // This targets the specific container often used for the feed
                css += "div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } "
            }
            
            if hideExplore {
                // 1. Target the specific GRID items on Explore, not the main container
                // Hide any link to a post or reel within the main area
                css += "main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } "
                
                // 2. Hide specific grid containers to remove whitespace/loaders if possible
                // Be careful not to hide the Search container at the top
                // Search usually is in a nav or top div, main grid is below
                css += "main[role='main'] > div > div:nth-child(n+2) { display: none !important; } "
            }
            
            if hideAds {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            // Common cleanup
            // Ensure inputs are visible!
            css += "input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }"
            
            let safeCSS = css.replacingOccurrences(of: "`", with: "\\`")
            
            let js = """
            (function() {
                var styleId = 'onyx-style';
                var style = document.getElementById(styleId);
                if (!style) {
                    style = document.createElement('style');
                    style.id = styleId;
                    document.head.appendChild(style);
                }
                style.textContent = `\(safeCSS)`;
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
