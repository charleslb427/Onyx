
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
        
        // Desktop UA (works for calls)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
        
        context.coordinator.webView = webView
        
        SessionManager.shared.restoreSession(to: webView) {
            if let url = URL(string: "https://www.instagram.com/") {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
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
            
            // EXPLORE: Hide "Découvrir/Explore" button completely
            if defaults.bool(forKey: "hideExplore") {
                css += "a[href='/explore/'], a[href='/explore'] { display: none !important; pointer-events: none !important; } "
                css += "a[aria-label='Découvrir'], a[aria-label='Explore'] { display: none !important; } "
            } else {
                css += "a[href='/explore/'], a[href*='/explore'] { opacity: 1 !important; visibility: visible !important; pointer-events: auto !important; } "
            }
            if defaults.bool(forKey: "hideAds") {
                css += "article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } "
            }
            
            css += """
                 @media (min-width: 0px) { body { --grid-numcols: 1 !important; font-size: 16px !important; } }
                 div[role="main"] { max-width: 100% !important; margin: 0 !important; }
                 nav[role="navigation"] { width: 100% !important; }
                 /* Keep sidebar visible for Search button - only hide specific desktop-only elements */
                 
                 /* 📱 REELS: Force larger display */
                 /* Only target Reels page specifically via URL check in JS */
                 
                 /* 📞 CUSTOM CALL LOBBY - Completely replaces Instagram's buggy lobby */
                 #onyx-custom-lobby {
                     position: fixed !important;
                     top: 0 !important;
                     left: 0 !important;
                     width: 100vw !important;
                     height: 100vh !important;
                     background: #000 !important;
                     z-index: 999999 !important;
                     display: flex !important;
                     flex-direction: column !important;
                 }
                 #onyx-custom-lobby .lobby-top {
                     flex: 1;
                     background: #1a1a1a;
                     display: flex;
                     align-items: center;
                     justify-content: center;
                     border-bottom: 1px solid #333;
                 }
                 #onyx-custom-lobby .lobby-bottom {
                     flex: 1;
                     background: #111;
                     display: flex;
                     flex-direction: column;
                     align-items: center;
                     justify-content: center;
                 }
                 #onyx-custom-lobby .user-avatar {
                     width: 80px;
                     height: 80px;
                     background: #404040;
                     border-radius: 50%;
                     display: flex;
                     align-items: center;
                     justify-content: center;
                     font-size: 36px;
                     margin-bottom: 16px;
                 }
                 #onyx-custom-lobby .username {
                     color: white;
                     font-size: 20px;
                     font-weight: 600;
                     margin-bottom: 8px;
                 }
                 #onyx-custom-lobby .call-status {
                     color: #888;
                     font-size: 14px;
                 }
                 #onyx-custom-lobby .controls {
                     position: absolute;
                     bottom: 120px;
                     display: flex;
                     gap: 24px;
                 }
                 #onyx-custom-lobby .control-btn {
                     width: 56px;
                     height: 56px;
                     background: #333;
                     border: none;
                     border-radius: 50%;
                     color: white;
                     font-size: 24px;
                     cursor: pointer;
                 }
                 #onyx-custom-lobby .control-btn.active { background: #0095f6; }
                 #onyx-custom-lobby .control-btn.off { background: #ff3b30; }
                 #onyx-custom-lobby .start-btn {
                     position: absolute;
                     bottom: 40px;
                     left: 50%;
                     transform: translateX(-50%);
                     width: calc(100% - 48px);
                     max-width: 320px;
                     height: 52px;
                     background: #0095f6;
                     color: white;
                     border: none;
                     border-radius: 12px;
                     font-size: 17px;
                     font-weight: 600;
                     cursor: pointer;
                 }
                 #onyx-custom-lobby .cancel-btn {
                     position: absolute;
                     top: 16px;
                     left: 16px;
                     background: rgba(255,255,255,0.1);
                     border: none;
                     color: white;
                     padding: 8px 16px;
                     border-radius: 20px;
                     font-size: 14px;
                     cursor: pointer;
                 }
                 
                 /* Hide original lobby when custom is active */
                 .onyx-lobby-hidden { opacity: 0 !important; pointer-events: none !important; position: absolute !important; left: -9999px !important; }
                 
                 /* 📞 ACTIVE CALL UI (when video is present) */
                 .onyx-call-active {
                    width: 100vw !important;
                    height: 100vh !important;
                    left: 0 !important;
                    top: 0 !important;
                    transform: scale(0.6) !important;
                    transform-origin: top left !important;
                 }
                 .onyx-call-active > div { width: 166% !important; height: 166% !important; }
                 .onyx-call-active div:has(button) {
                    bottom: 20px !important;
                    max-width: 100% !important;
                    flex-wrap: wrap !important;
                    justify-content: center !important;
                    gap: 10px !important;
                 }
                 .onyx-call-active button { transform: scale(1.2); margin: 5px !important; }
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
                
                // 🎯 CUSTOM LOBBY LOGIC
                var customLobbyActive = false;
                var originalLobbyRef = null;
                var micEnabled = true;
                var camEnabled = false;
                
                function createCustomLobby(originalDialog) {
                    if (document.getElementById('onyx-custom-lobby')) return;
                    
                    customLobbyActive = true;
                    originalLobbyRef = originalDialog;
                    
                    // Hide original
                    originalDialog.classList.add('onyx-lobby-hidden');
                    
                    // Extract username from dialog if possible
                    var usernameText = 'Appel en cours...';
                    var userSpan = originalDialog.querySelector('span');
                    if (userSpan && userSpan.textContent.length < 30) {
                        usernameText = userSpan.textContent;
                    }
                    
                    var lobby = document.createElement('div');
                    lobby.id = 'onyx-custom-lobby';
                    lobby.innerHTML = `
                        <button class="cancel-btn" id="onyx-cancel-call">✕ Annuler</button>
                        <div class="lobby-top">
                            <span style="color:#666;font-size:14px;">📹 Caméra désactivée</span>
                        </div>
                        <div class="lobby-bottom">
                            <div class="user-avatar">👤</div>
                            <div class="username">${usernameText}</div>
                            <div class="call-status">Prêt(e) à démarrer ?</div>
                        </div>
                        <div class="controls">
                            <button class="control-btn active" id="onyx-mic-btn">🎤</button>
                            <button class="control-btn off" id="onyx-cam-btn">📷</button>
                        </div>
                        <button class="start-btn" id="onyx-start-call">Démarrer l'appel</button>
                    `;
                    document.body.appendChild(lobby);
                    
                    // Event: Cancel
                    document.getElementById('onyx-cancel-call').onclick = function() {
                        destroyCustomLobby();
                        // Click cancel in original dialog
                        var cancelBtn = originalDialog.querySelector('button[aria-label*="Annuler"], button[aria-label*="Cancel"], button[aria-label*="Fermer"], button[aria-label*="Close"]');
                        if (cancelBtn) cancelBtn.click();
                        else window.history.back();
                    };
                    
                    // Event: Mic toggle
                    document.getElementById('onyx-mic-btn').onclick = function() {
                        micEnabled = !micEnabled;
                        this.className = 'control-btn ' + (micEnabled ? 'active' : 'off');
                        // Try to click original mic button
                        var micBtn = originalDialog.querySelector('button[aria-label*="Micro"], button[aria-label*="Mic"]');
                        if (micBtn) micBtn.click();
                    };
                    
                    // Event: Cam toggle
                    document.getElementById('onyx-cam-btn').onclick = function() {
                        camEnabled = !camEnabled;
                        this.className = 'control-btn ' + (camEnabled ? 'active' : 'off');
                        // Try to click original camera button
                        var camBtn = originalDialog.querySelector('button[aria-label*="Caméra"], button[aria-label*="Camera"], button[aria-label*="Vidéo"], button[aria-label*="Video"]');
                        if (camBtn) camBtn.click();
                    };
                    
                    // Event: Start Call
                    document.getElementById('onyx-start-call').onclick = function() {
                        console.log('🚀 Starting call...');
                        // Find and click the real start button
                        var buttons = originalDialog.querySelectorAll('button');
                        var startBtn = null;
                        buttons.forEach(function(btn) {
                            var txt = (btn.textContent || '').toLowerCase();
                            var label = (btn.getAttribute('aria-label') || '').toLowerCase();
                            if (txt.includes('démarrer') || txt.includes('start') || txt.includes('rejoindre') || txt.includes('join') ||
                                label.includes('démarrer') || label.includes('start') || label.includes('rejoindre') || label.includes('join')) {
                                startBtn = btn;
                            }
                        });
                        
                        if (startBtn) {
                            console.log('✅ Found start button, clicking...');
                            startBtn.click();
                            setTimeout(function() { destroyCustomLobby(); }, 300);
                        } else {
                            console.log('❌ Start button not found, trying first prominent button');
                            // Fallback: click the first blue/primary button
                            var primaryBtn = originalDialog.querySelector('button[style*="background"]');
                            if (primaryBtn) primaryBtn.click();
                            setTimeout(function() { destroyCustomLobby(); }, 300);
                        }
                    };
                    
                    console.log('✅ Custom lobby created');
                }
                
                function destroyCustomLobby() {
                    var lobby = document.getElementById('onyx-custom-lobby');
                    if (lobby) lobby.remove();
                    if (originalLobbyRef) {
                        originalLobbyRef.classList.remove('onyx-lobby-hidden');
                    }
                    customLobbyActive = false;
                    originalLobbyRef = null;
                }
                
                function cleanContent() {
                     \(defaults.bool(forKey: "hideExplore") ? """
                     // Hide loading spinners
                     var loaders = document.querySelectorAll('svg[aria-label=\"Chargement...\"], svg[aria-label=\"Loading...\"]');
                     loaders.forEach(l => l.style.display = 'none');
                     """ : "")
                     
                     // 🕵️ DETECT CALL DIALOGS
                     var dialogs = document.querySelectorAll('div[role="dialog"]');
                     dialogs.forEach(function(d) {
                        var text = d.innerText || "";
                        var textLower = text.toLowerCase();
                        
                        // Check for active video call (has video element playing)
                        var hasActiveVideo = d.querySelector('video[srcObject], video:not([src=""])');
                        var hasMedia = d.querySelector('video') || d.querySelector('audio');
                        
                        // Check for lobby keywords
                        var isLobbyKeywords = text.includes("Rejoindre") || text.includes("Join") || 
                                              text.includes("Prêt") || text.includes("Ready") ||
                                              text.includes("Démarrer l'appel") || text.includes("Start call");
                        
                        // Check for call buttons
                        var hasCallButtons = d.querySelector('button[aria-label*="Micro"]') || 
                                             d.querySelector('button[aria-label*="Caméra"]') ||
                                             d.querySelector('button[aria-label*="Mic"]') ||
                                             d.querySelector('button[aria-label*="Camera"]');
                        
                        // Exclude cookie/legal dialogs
                        var isCookieOrLegal = text.includes('Cookies') || text.includes('confidentialité') || 
                                              text.includes('Paramètres optionnels') || text.includes('privacy');
                        
                        // CASE 1: LOBBY (pre-call, no active video yet)
                        if ((isLobbyKeywords || hasCallButtons) && !hasActiveVideo && !isCookieOrLegal) {
                            // Create custom lobby if not already active
                            if (!customLobbyActive) {
                                createCustomLobby(d);
                            }
                            return;
                        }
                        
                        // CASE 2: ACTIVE CALL (has video playing)
                        if (hasActiveVideo && !isCookieOrLegal) {
                            // Destroy custom lobby if it exists
                            if (customLobbyActive) destroyCustomLobby();
                            
                            // Apply scaling fix for active call
                            d.classList.add('onyx-call-active');
                            d.classList.remove('onyx-lobby-hidden');
                            
                            // EXIT BUTTON when call ends
                            if (textLower.includes("appel terminé") || textLower.includes("call ended")) {
                                if (!document.getElementById('onyx-exit-btn')) {
                                    var btn = document.createElement('button');
                                    btn.id = 'onyx-exit-btn';
                                    btn.innerText = "Quitter";
                                    btn.style.cssText = "position:absolute; top:40px; right:20px; z-index:9999; padding:10px 20px; background:white; color:black; border-radius:20px; font-weight:bold; box-shadow:0 2px 10px rgba(0,0,0,0.2);";
                                    btn.onclick = function() { window.location.href = '/direct/inbox/'; };
                                    d.appendChild(btn);
                                }
                            }
                            return;
                        }
                        
                        // CASE 3: Not a call dialog
                        d.classList.remove('onyx-call-active');
                        d.classList.remove('onyx-lobby-hidden');
                     });
                     
                     // If no lobby dialog exists anymore, clean up custom lobby
                     if (customLobbyActive) {
                         var anyLobby = document.querySelector('div[role="dialog"]');
                         if (!anyLobby) destroyCustomLobby();
                     }
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
