
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
        
        // --- EARLY CSS INJECTION & SPOOFING ---
        let earlyHideScript = """
        (function() {
            // 1. Hide Elements Flash
            var style = document.createElement('style');
            style.id = 'onyx-early-hide';
            style.textContent = 'a[href*="/reels/"], a[href="/reels/"], a[href="/explore/"], a[href*="/explore"], div[role="banner"], footer { opacity: 0 !important; transition: opacity 0.1s; }';
            document.documentElement.appendChild(style);
            
            // 2. Spoof PWA Standalone Mode (Unlock Features?)
            try {
                Object.defineProperty(window.navigator, 'standalone', {
                    get: function() { return true; }
                });
            } catch(e) {}
        })();
        """
        let earlyHideUserScript = WKUserScript(source: earlyHideScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(earlyHideUserScript)
        
        // --- SAVE SESSION ON BACKGROUND ---
        // We add an observer here or in Coordinator to save when user leaves
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            // This is tricky inside makeUIView, better handled in Coordinator context or via specific save call
             // Actually, we can't easily access the webview instance here to save.
             // We'll delegate this to the Coordinator via the Notification bridge or a global reference?
             // Simplest: The Coordinator observes it.
        }
        
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
        
        // Update UA to iPad (Tablet) to try unlocking Calls/Voice Msg
        // "Macintosh" often forces desktop site (too small), iPad is the best balance.
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
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
        
        override init() {
            super.init()
            // ✅ AUTO SAVE on App Background/Close to prevent data loss
            NotificationCenter.default.addObserver(self, selector: #selector(saveSessionNow), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(saveSessionNow), name: UIApplication.willTerminateNotification, object: nil)
        }
        
        @objc func saveSessionNow() {
            guard let wv = webView else { return }
            print("💾 Saving session before background/close...")
            SessionManager.shared.saveSession(from: wv)
        }
        
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
            if defaults.bool(forKey: "hideReels") {
                if urlString == "https://www.instagram.com/reels/" || urlString.contains("/reels/audio/") {
                     decisionHandler(.cancel)
                     return
                }
            }
            
            // 3. PREVENT SWIPE BACK TO LOGIN (Fix accidental logout)
            let isBackForward = navigationAction.navigationType == .backForward
            if isBackForward && (urlString.contains("/accounts/login") || urlString.contains("/accounts/emailsignup")) {
                decisionHandler(.cancel)
                return
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
                // 1. STRICT BLOCKING of Feed Items (Posts & Reels)
                // We target links to specific content.
                // Search results (Users, Hashtags) are safely ignored as they don't start with /p/ or /reel/
                css += "main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } "
                
                // 2. Hide Loaders/Spinners
                // If the feed is empty, Insta might show a loader. Hide it.
                css += "svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } "
                
                // 3. Hide the div that typically holds the grid to collapse whitespace
                // (Only if it strictly contains posts, avoiding search containers)
                // css += "div:has(> a[href^='/p/']) { display: none !important; }" // Too risky for now, stick to item hiding
            }
            
            if hideAds {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            // Common cleanup
            // FORCE SEARCH VISIBILITY
            // Inputs, Dialogs (Results), and Links to Users/Tags must be visible
            css += "input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } "
            css += "a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; }"
            
            css += "div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }"
            
            let safeCSS = css.replacingOccurrences(of: "`", with: "\\`")
            
            // ✅ MUTATION OBSERVER SCRIPT
            // This actively watches for new content loaded by scrolling/interaction and hides it
            let js = """
            (function() {
                // 1. Inject Style Rule
                var styleId = 'onyx-style';
                var style = document.getElementById(styleId);
                if (!style) {
                    style = document.createElement('style');
                    style.id = styleId;
                    document.head.appendChild(style);
                }
                style.textContent = `\(safeCSS)`;
                
                // 2. JS Cleanup (Backup for CSS)
                function cleanContent() {
                    \(hideExplore ? "var loaders = document.querySelectorAll('svg[aria-label=\"Chargement...\"], svg[aria-label=\"Loading...\"]'); loaders.forEach(l => l.style.display = 'none');" : "")
                }
                
                // 3. Setup Observer
                if (!window.onyxObserver) {
                    cleanContent();
                    window.onyxObserver = new MutationObserver(function(mutations) {
                        cleanContent();
                    });
                    window.onyxObserver.observe(document.body, { childList: true, subtree: true });
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
