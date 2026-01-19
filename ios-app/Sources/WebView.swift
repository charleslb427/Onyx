
import SwiftUI
import WebKit
import UserNotifications
import AVFoundation

struct WebViewWrapper: UIViewRepresentable {
    @Binding var refreshTrigger: UUID
    
    private func requestNativePermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        requestNativePermissions()
        
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        config.processPool = AppDelegate.shared.webViewProcessPool
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // --- EARLY CONFIG ---
        let earlyHideScript = """
        (function() {
            var style = document.createElement('style');
            style.id = 'onyx-early-hide';
            style.textContent = 'a[href*="/reels/"], a[href="/reels/"], a[href="/explore/"], a[href*="/explore"], div[role="banner"], footer { opacity: 0 !important; transition: opacity 0.1s; }';
            document.documentElement.appendChild(style);
            
            try { Object.defineProperty(window.navigator, 'standalone', { get: function() { return true; } }); } catch(e) {}
            try { Object.defineProperty(navigator, 'webdriver', { get: () => false }); Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] }); } catch(e) {}
            try { localStorage.setItem('display_version', 'mobile'); } catch(e) {}
        })();
        """
        let earlyHideUserScript = WKUserScript(source: earlyHideScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(earlyHideUserScript)
        
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

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
        
        webView.allowsBackForwardNavigationGestures = false
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        // iPad Tablet UA (enables calls + keeps mobile-like UI)
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
        
        context.coordinator.webView = webView
        
        SessionManager.shared.restoreSession(to: webView) {
            if let url = URL(string: "https://www.instagram.com/") {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                request.setValue("https://www.instagram.com", forHTTPHeaderField: "Referer")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
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

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if !hasInjectedLocalStorage {
                SessionManager.shared.injectLocalStorage(to: webView)
                hasInjectedLocalStorage = true
            }
            injectFilters(into: webView)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let urlString = url.absoluteString
            
            if urlString == "about:blank" || urlString.isEmpty { decisionHandler(.cancel); return }
            
            if UserDefaults.standard.bool(forKey: "hideReels") {
                if urlString == "https://www.instagram.com/reels/" || urlString.contains("/reels/audio/") { decisionHandler(.cancel); return }
            }
            
            let isBackForward = navigationAction.navigationType == .backForward
            if isBackForward && (urlString.contains("/accounts/login") || urlString.contains("/accounts/emailsignup")) { decisionHandler(.cancel); return }

            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
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
            
            var css = ""
            
            // REELS: Hide or restore visibility
            if defaults.bool(forKey: "hideReels") {
                css += "a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; pointer-events: none !important; } "
                css += "a[href*='/reels/'] { display: none !important; pointer-events: none !important; } " 
                css += "div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } "
            } else {
                // RESTORE visibility (counter early-hide opacity:0)
                css += "a[href='/reels/'], a[href*='/reels/'] { opacity: 1 !important; visibility: visible !important; pointer-events: auto !important; } "
            }
            
            // EXPLORE: Hide or restore visibility
            if defaults.bool(forKey: "hideExplore") {
                css += "a[href='/explore/'], a[href*='/explore'] { display: none !important; pointer-events: none !important; } "
                css += "main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; pointer-events: none !important; } "
                css += "svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } "
            } else {
                // RESTORE visibility (counter early-hide opacity:0)
                css += "a[href='/explore/'], a[href*='/explore'] { opacity: 1 !important; visibility: visible !important; pointer-events: auto !important; } "
            }
            if defaults.bool(forKey: "hideAds") {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            css += """
                 @media (min-width: 0px) { body { --grid-numcols: 1 !important; font-size: 16px !important; } }
                 div[role="main"] { max-width: 100% !important; margin: 0 !important; }
                 nav[role="navigation"] { width: 100% !important; }
                 [class*="sidebar"], [class*="desktop"] { display: none !important; }
                 
                 /* 📞 CALL UI MAGIC (Applied conditionally via JS class .onyx-call-ui) */
                 .onyx-call-ui {
                    width: 100vw !important;
                    height: 100vh !important;
                    left: 0 !important;
                    top: 0 !important;
                    transform: scale(0.6) !important;
                    transform-origin: top left !important;
                 }
                 .onyx-call-ui > div { width: 166% !important; height: 166% !important; }
                 
                 .onyx-call-ui div:has(button) {
                    bottom: 20px !important;
                    max-width: 100% !important;
                    flex-wrap: wrap !important;
                    justify-content: center !important;
                    gap: 10px !important;
                 }
                 .onyx-call-ui button { transform: scale(1.2); margin: 5px !important; }
            """
            
            css += "input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } "
            css += "a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; }"
            css += "div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }"
            
            let safeCSS = css.replacingOccurrences(of: "`", with: "\\`")
            
            let js = """
            (function() {
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes, viewport-fit=cover';
                
                var styleId = 'onyx-style';
                var style = document.getElementById(styleId);
                if (!style) {
                    style = document.createElement('style');
                    style.id = styleId;
                    document.head.appendChild(style);
                }
                style.textContent = `\(safeCSS)`;
                
                function cleanContent() {
                     \(defaults.bool(forKey: "hideExplore") ? "var loaders = document.querySelectorAll('svg[aria-label=\"Chargement...\"], svg[aria-label=\"Loading...\"]'); loaders.forEach(l => l.style.display = 'none');" : "")
                     
                     // 🕵️ DETECT CALL DIALOG (Active Call OR Pre-Call Lobby) vs COOKIE DIALOG
                     var dialogs = document.querySelectorAll('div[role="dialog"]');
                     dialogs.forEach(d => {
                        var text = d.innerText || "";
                        
                        // 1. IS IT A CALL?
                        // - Contains video/audio elements
                        // - OR Contains mic/cam buttons
                        // - OR Contains LOBBY Keywords ("Rejoindre l'appel", "Join call", "Ready to join")
                        var hasMedia = d.querySelector('video') || d.querySelector('audio');
                        var hasCallButtons = d.querySelector('button svg') || d.querySelector('button[aria-label*="Micro"]');
                        var isLobby = text.includes("Rejoindre") || text.includes("Join") || text.includes("Prêt") || text.includes("Ready");
                        
                        var isCall = hasMedia || hasCallButtons || isLobby;
                        
                        // 2. IS IT JUST TEXT/COOKIES?
                        // Avoid false positives if "Rejoindre" is used in legal text (unlikely but safe)
                        var isCookieOrLegal = text.includes('Cookies') || text.includes('confidentialité') || text.includes('Paramètres optionnels');
                        
                        // Apply Apply Call Fix
                        if (isCall && !isCookieOrLegal) {
                            d.classList.add('onyx-call-ui');
                            
                            // 3. EXIT HATCH: Detect "Call Ended" state inside the dialog
                            var cleanText = d.innerText.toLowerCase();
                            if (cleanText.includes("appel terminé") || cleanText.includes("call ended") || cleanText.includes("appel fini")) {
                                if (!document.getElementById('onyx-exit-btn')) {
                                    var btn = document.createElement('button');
                                    btn.id = 'onyx-exit-btn';
                                    btn.innerText = "Quitter";
                                    btn.style.cssText = "position:absolute; top:40px; right:20px; z-index:9999; padding:10px 20px; background:white; color:black; border-radius:20px; font-weight:bold; box-shadow:0 2px 10px rgba(0,0,0,0.2);";
                                    btn.onclick = function() { window.location.href = '/direct/inbox/'; };
                                    d.appendChild(btn);
                                }
                            }
                        } else {
                            d.classList.remove('onyx-call-ui');
                        }
                     });
                }
                
                if (!window.onyxObserver) {
                    cleanContent();
                    window.onyxObserver = new MutationObserver(function(mutations) { cleanContent(); });
                    window.onyxObserver.observe(document.body, { childList: true, subtree: true });
                }
                
                document.addEventListener('touchend', function(e) {
                    var touch = e.changedTouches[0];
                    var target = document.elementFromPoint(touch.clientX, touch.clientY);
                    var clickable = target ? target.closest('button, [role="button"], a, svg') : null;
                    
                    // Only shim if it's a call-related button to be safe, or general buttons
                    // For now, keep generic but add anti-double-tap
                    if (clickable) {
                        // Prevent native click to avoid "Double Tap" bug (Join -> Cancel)
                        if (e.cancelable) e.preventDefault();
                        
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
                }, {passive: false}); // 👈 IMPORTANT: passive: false allows preventDefault
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
