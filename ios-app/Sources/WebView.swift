
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
            
            // 3. 🛡️ ANTI-DETECTION (Partial): HIDE WEBVIEW
            // Tricks Instagram stealth checks
            try {
                Object.defineProperty(navigator, 'webdriver', { get: () => false });
                Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
                // NOTE: We do NOT spoof window.innerWidth here anymore to allow responsive UI
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
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
        
        context.coordinator.webView = webView
        
        // ✅ RESTORE SESSION THEN LOAD WITH HEADERS
        SessionManager.shared.restoreSession(to: webView) {
            if let url = URL(string: "https://www.instagram.com/") {
                var request = URLRequest(url: url)
                // 🛡️ STEALTH HEADERS
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("https://www.instagram.com", forHTTPHeaderField: "Referer")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
                request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
                request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
                
                webView.load(request)
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

        // --- NAVIGATION ---
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if !hasInjectedLocalStorage {
                SessionManager.shared.injectLocalStorage(to: webView)
                hasInjectedLocalStorage = true
            }
            injectFilters(into: webView)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let urlString = url.absoluteString
            let defaults = UserDefaults.standard
            
            if urlString == "about:blank" || urlString.isEmpty {
                decisionHandler(.cancel)
                return
            }
            
            if defaults.bool(forKey: "hideReels") {
                if urlString == "https://www.instagram.com/reels/" || urlString.contains("/reels/audio/") {
                     decisionHandler(.cancel)
                     return
                }
            }
            
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
            
            if let url = webView.url?.absoluteString, url == "https://www.instagram.com/" {
                webView.allowsBackForwardNavigationGestures = false
            } else {
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
                css += "a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; } "
                css += "a[href*='/reels/'] { display: none !important; } " 
                css += "div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } "
            }
            
            if hideExplore {
                css += "main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } "
                css += "svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } "
            }
            
            if hideAds {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            // 🚀 FORCE MOBILE LAYOUT (CSS) for Desktop UA
            css += """
                 @media (min-width: 0px) { body { --grid-numcols: 1 !important; font-size: 16px !important; } }
                 div[role="main"] { max-width: 100% !important; margin: 0 !important; }
                 nav[role="navigation"] { width: 100% !important; }
                 [class*="sidebar"], [class*="desktop"] { display: none !important; }
            """
            
            // Common cleanup & FORCE SEARCH VISIBILITY
            css += "input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } "
            css += "a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }"
            
            let safeCSS = css.replacingOccurrences(of: "`", with: "\\`")
            
            // ✅ MUTATION OBSERVER & TOUCH SHIM V2
            let js = """
            (function() {
                // 0. Force Mobile Viewport (Vital for Desktop UA on Mobile)
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
                
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
                
                // 4. TOUCH SHIM V2 (Pointer Events Support)
                document.addEventListener('touchend', function(e) {
                    var touch = e.changedTouches[0];
                    var target = document.elementFromPoint(touch.clientX, touch.clientY);
                    var clickable = target ? target.closest('button, [role="button"], a, svg') : null;
                    if (clickable) {
                        var opts = {
                            view: window, bubbles: true, cancelable: true,
                            clientX: touch.clientX, clientY: touch.clientY, screenX: touch.screenX, screenY: touch.screenY,
                            pointerType: 'touch', isPrimary: true
                        };
                        clickable.dispatchEvent(new PointerEvent('pointerdown', opts));
                        clickable.dispatchEvent(new MouseEvent('mousedown', opts));
                        clickable.dispatchEvent(new PointerEvent('pointerup', opts));
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
