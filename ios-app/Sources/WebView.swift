
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
            // Initially hide potentially blocked content to reduce flash
            style.textContent = 'a[href*="/reels/"], a[href="/reels/"], a[href="/explore/"], a[href*="/explore"], div[role="banner"], footer { opacity: 0 !important; transition: opacity 0.1s; }';
            document.documentElement.appendChild(style);
            
            // 2. Spoof PWA Standalone Mode (Attempt to unlock PWA features)
            try {
                Object.defineProperty(window.navigator, 'standalone', {
                    get: function() { return true; }
                });
            } catch(e) {}
        })();
        """
        let earlyHideUserScript = WKUserScript(source: earlyHideScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(earlyHideUserScript)
        
        // ALLOW POPUPS (Calls)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

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
        
        // 🖥️ DESKTOP UA with MOBILE SPOOFING
        // We use a Desktop User Agent to unlock Calls/Voice Messages (which are hidden on Mobile Web)
        // AND we inject a viewport meta tag via JS (in injectFilters) to force it to render like a mobile app.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
        
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
        // ✅ HANDLE POPUPS (Force open in same WebView)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
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
                // 3. Anti-Doomscroll
                css += "div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } "
            }
            
            if hideExplore {
                // 1. STRICT BLOCKING of Feed Items (Posts & Reels)
                css += "main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } "
                // 2. Hide Loaders/Spinners
                css += "svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } "
            }
            
            if hideAds {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            // FORCE SEARCH VISIBILITY
            css += "input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } "
            css += "a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; }"
            
            css += "div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }"
            
            let safeCSS = css.replacingOccurrences(of: "`", with: "\\`")
            
            // ✅ MUTATION OBSERVER & VIEWPORT FIX (Force Mobile Scale on Desktop UA)
            let js = """
            (function() {
                // 0. Force Mobile Viewport (Vital for Desktop UA on Mobile)
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                
                // 1. Inject Style Rule
                var styleId = 'onyx-style';
                var style = document.getElementById(styleId);
                if (!style) {
                    style = document.createElement('style');
                    style.id = styleId;
                    document.head.appendChild(style);
                }
                style.textContent = `\(safeCSS)`;
                
                // 2. JS Cleanup Loop
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
                
                // 4. TOUCH SHIM (Vital for Desktop Mode on Mobile)
                // Forces a 'click' event when touching buttons, as Desktop site might ignore touch
                document.addEventListener('touchend', function(e) {
                    var touch = e.changedTouches[0];
                    var target = document.elementFromPoint(touch.clientX, touch.clientY);
                    // Find closest clickable element
                    var clickable = target.closest('button, [role="button"], a, svg');
                    if (clickable) {
                        // Dispatch synthetic Mouse Events
                        var opts = {
                            view: window, bubbles: true, cancelable: true,
                            clientX: touch.clientX, clientY: touch.clientY, screenX: touch.screenX, screenY: touch.screenY
                        };
                        clickable.dispatchEvent(new MouseEvent('mousedown', opts));
                        clickable.dispatchEvent(new MouseEvent('mouseup', opts));
                        clickable.dispatchEvent(new MouseEvent('click', opts));
                    }
                }, {passive: true});
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
