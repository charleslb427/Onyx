package com.onyx.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.webkit.*
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.preference.PreferenceManager
import com.onyx.app.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var webView: WebView
    private var pendingPermissionRequest: PermissionRequest? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            pendingPermissionRequest?.let { request ->
                request.grant(request.resources)
                pendingPermissionRequest = null
            }
        } else {
            pendingPermissionRequest?.deny()
            pendingPermissionRequest = null
            Toast.makeText(this, "Permissions requises pour les appels", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.hide()

        setupNotifications()
        setupWebView()
        setupSwipeRefresh()
        setupFab()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        intent?.let { handleIntent(it) }
    }

    private fun handleIntent(intent: Intent) {
        val targetUrl = intent.getStringExtra("target_url")
        val headers = getHeaders()
        if (targetUrl != null) {
            webView.loadUrl(targetUrl, headers)
        } else if (webView.url == null) {
             webView.loadUrl("https://www.instagram.com/", headers)
        }
    }

    private fun getHeaders(): Map<String, String> {
        return mapOf(
            "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer" to "https://www.instagram.com/",
            "Accept-Language" to "en-US,en;q=0.9",
            "Accept-Encoding" to "gzip, deflate, br",
            "Accept" to "*/*",
            "Sec-Fetch-Dest" to "document",
            "Sec-Fetch-Mode" to "navigate",
            "Sec-Fetch-Site" to "none"
        )
    }

    private fun setupNotifications() {
        createNotificationChannels()
        requestNotificationPermission()
        checkNotificationListenerPermission()
    }

    private fun setupSwipeRefresh() {
        binding.swipeRefresh.setOnRefreshListener {
            webView.reload()
        }
    }

    private fun setupFab() {
        binding.fabSettings.setImageResource(R.drawable.ic_settings_fab)
        binding.fabSettings.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            val messageChannel = NotificationChannel("onyx_messages", getString(R.string.notification_channel_name), NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Messages Instagram via Onyx"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(messageChannel)
            
            val callChannel = NotificationChannel("onyx_calls", getString(R.string.notification_channel_calls), NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Appels Instagram via Onyx"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(callChannel)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    private fun checkNotificationListenerPermission() {
        val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(this)
        if (!enabledListeners.contains(packageName)) { }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView = binding.webView
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT 
            
            loadWithOverviewMode = true
            useWideViewPort = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = false
            javaScriptCanOpenWindowsAutomatically = true
            // Desktop UA (works for calls)
            userAgentString = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            
            setSupportMultipleWindows(true)
            setRenderPriority(WebSettings.RenderPriority.HIGH)
        }

        webView.isVerticalScrollBarEnabled = false 
        webView.isHorizontalScrollBarEnabled = false
        
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                binding.progressBar.visibility = View.VISIBLE
                injectFilters()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                binding.progressBar.visibility = View.GONE
                binding.swipeRefresh.isRefreshing = false
                injectFilters()
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                val prefs = PreferenceManager.getDefaultSharedPreferences(this@MainActivity)
                val hideReels = prefs.getBoolean("hide_reels", true)
                
                if (hideReels) {
                    if (url == "https://www.instagram.com/reels/" || url.contains("/reels/audio/")) { return true }
                }
                
                if (url.contains("instagram.com")) { return false }
                
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (e: Exception) { }
                return true
            }

        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?): Boolean {
                val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                transport.webView = view
                resultMsg.sendToTarget()
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) return
                val resources = request.resources
                val androidPermissions = mutableListOf<String>()
                if (resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) { androidPermissions.add(Manifest.permission.CAMERA) }
                if (resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) { androidPermissions.add(Manifest.permission.RECORD_AUDIO); androidPermissions.add(Manifest.permission.MODIFY_AUDIO_SETTINGS) }

                val missingPermissions = androidPermissions.filter { ContextCompat.checkSelfPermission(this@MainActivity, it) != PackageManager.PERMISSION_GRANTED }
                if (missingPermissions.isEmpty()) { request.grant(resources) } 
                else {
                    pendingPermissionRequest = request
                    permissionLauncher.launch(missingPermissions.toTypedArray())
                }
            }
            
            override fun onPermissionRequestCanceled(request: PermissionRequest?) {
                if (pendingPermissionRequest == request) { pendingPermissionRequest = null }
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                if (newProgress > 10) injectFilters() 
                if (newProgress == 100) { binding.progressBar.visibility = View.GONE; binding.swipeRefresh.isRefreshing = false }
            }
        }
    }

    private fun injectFilters() {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        val hideReels = prefs.getBoolean("hide_reels", true)
        val hideExplore = prefs.getBoolean("hide_explore", true)
        val hideAds = prefs.getBoolean("hide_ads", true)

        val cssRules = StringBuilder()
        
        // REELS: Hide or restore visibility
        if (hideReels) {
            cssRules.append("a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; pointer-events: none !important; } ")
            cssRules.append("a[href*='/reels/'] { display: none !important; pointer-events: none !important; } ") 
            cssRules.append("div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } ")
        } else {
            // RESTORE visibility (counter any early-hide)
            cssRules.append("a[href='/reels/'], a[href*='/reels/'] { opacity: 1 !important; visibility: visible !important; pointer-events: auto !important; } ")
        }
        
        // EXPLORE: Hide "Découvrir/Explore" button completely
        if (hideExplore) {
            cssRules.append("a[href='/explore/'], a[href='/explore'] { display: none !important; pointer-events: none !important; } ")
            cssRules.append("a[aria-label='Découvrir'], a[aria-label='Explore'] { display: none !important; } ")
        } else {
            cssRules.append("a[href='/explore/'], a[href*='/explore'] { opacity: 1 !important; visibility: visible !important; pointer-events: auto !important; } ")
        }
        
        if (hideAds) {
            cssRules.append("article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } ")
        }
        
        // Mobile Layout Force
        cssRules.append("@media (min-width: 0px) { body { --grid-numcols: 1 !important; font-size: 16px !important; } } ")
        cssRules.append("div[role='main'] { max-width: 100% !important; margin: 0 !important; } ")
        cssRules.append("nav[role='navigation'] { width: 100% !important; } ")
        // Keep sidebar visible for Search button
        
        // 📱 REELS: Will be handled conditionally in JS based on URL
        
        // 📞 CUSTOM CALL LOBBY - Completely replaces Instagram's buggy lobby
        cssRules.append("""
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
            .onyx-lobby-hidden { opacity: 0 !important; pointer-events: none !important; position: absolute !important; left: -9999px !important; }
            .onyx-call-active { width: 100vw !important; height: 100vh !important; left: 0 !important; top: 0 !important; transform: scale(0.6) !important; transform-origin: top left !important; }
            .onyx-call-active > div { width: 166% !important; height: 166% !important; }
            .onyx-call-active div:has(button) { bottom: 20px !important; max-width: 100% !important; flex-wrap: wrap !important; justify-content: center !important; gap: 10px !important; }
            .onyx-call-active button { transform: scale(1.2); margin: 5px !important; }
        """)
        
        cssRules.append("input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; } ")
        cssRules.append("div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } ")
        cssRules.append("a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; } ")
        cssRules.append("div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }")

        val safeCSS = cssRules.toString().replace("`", "\\`")

        val js = """
            (function() {
                try { Object.defineProperty(navigator, 'webdriver', { get: () => false }); Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] }); } catch(e) {}
                try { localStorage.setItem('display_version', 'mobile'); } catch(e) {}
            
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
                style.textContent = `$safeCSS`;
                
                // 🎯 CUSTOM LOBBY LOGIC
                var customLobbyActive = false;
                var originalLobbyRef = null;
                var micEnabled = true;
                var camEnabled = false;
                
                function createCustomLobby(originalDialog) {
                    if (document.getElementById('onyx-custom-lobby')) return;
                    
                    customLobbyActive = true;
                    originalLobbyRef = originalDialog;
                    
                    originalDialog.classList.add('onyx-lobby-hidden');
                    
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
                            <div class="username">${'$'}{usernameText}</div>
                            <div class="call-status">Prêt(e) à démarrer ?</div>
                        </div>
                        <div class="controls">
                            <button class="control-btn active" id="onyx-mic-btn">🎤</button>
                            <button class="control-btn off" id="onyx-cam-btn">📷</button>
                        </div>
                        <button class="start-btn" id="onyx-start-call">Démarrer l'appel</button>
                    `;
                    document.body.appendChild(lobby);
                    
                    document.getElementById('onyx-cancel-call').onclick = function() {
                        destroyCustomLobby();
                        var cancelBtn = originalDialog.querySelector('button[aria-label*="Annuler"], button[aria-label*="Cancel"], button[aria-label*="Fermer"], button[aria-label*="Close"]');
                        if (cancelBtn) cancelBtn.click();
                        else window.history.back();
                    };
                    
                    document.getElementById('onyx-mic-btn').onclick = function() {
                        micEnabled = !micEnabled;
                        this.className = 'control-btn ' + (micEnabled ? 'active' : 'off');
                        var micBtn = originalDialog.querySelector('button[aria-label*="Micro"], button[aria-label*="Mic"]');
                        if (micBtn) micBtn.click();
                    };
                    
                    document.getElementById('onyx-cam-btn').onclick = function() {
                        camEnabled = !camEnabled;
                        this.className = 'control-btn ' + (camEnabled ? 'active' : 'off');
                        var camBtn = originalDialog.querySelector('button[aria-label*="Caméra"], button[aria-label*="Camera"], button[aria-label*="Vidéo"], button[aria-label*="Video"]');
                        if (camBtn) camBtn.click();
                    };
                    
                    document.getElementById('onyx-start-call').onclick = function() {
                        console.log('🚀 Starting call...');
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
                     ${if (hideExplore) """
                     var loaders = document.querySelectorAll('svg[aria-label="Chargement..."], svg[aria-label="Loading..."]');
                     loaders.forEach(l => l.style.display = 'none');
                     """ else ""}
                     
                     var dialogs = document.querySelectorAll('div[role="dialog"]');
                     dialogs.forEach(function(d) {
                        var text = d.innerText || "";
                        var textLower = text.toLowerCase();
                        
                        var hasActiveVideo = d.querySelector('video[srcObject], video:not([src=""])');
                        var hasMedia = d.querySelector('video') || d.querySelector('audio');
                        
                        var isLobbyKeywords = text.includes("Rejoindre") || text.includes("Join") || 
                                              text.includes("Prêt") || text.includes("Ready") ||
                                              text.includes("Démarrer l'appel") || text.includes("Start call");
                        
                        var hasCallButtons = d.querySelector('button[aria-label*="Micro"]') || 
                                             d.querySelector('button[aria-label*="Caméra"]') ||
                                             d.querySelector('button[aria-label*="Mic"]') ||
                                             d.querySelector('button[aria-label*="Camera"]');
                        
                        var isCookieOrLegal = text.includes('Cookies') || text.includes('confidentialité') || 
                                              text.includes('Paramètres optionnels') || text.includes('privacy');
                        
                        if ((isLobbyKeywords || hasCallButtons) && !hasActiveVideo && !isCookieOrLegal) {
                            if (!customLobbyActive) {
                                createCustomLobby(d);
                            }
                            return;
                        }
                        
                        if (hasActiveVideo && !isCookieOrLegal) {
                            if (customLobbyActive) destroyCustomLobby();
                            
                            d.classList.add('onyx-call-active');
                            d.classList.remove('onyx-lobby-hidden');
                            
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
                        
                        d.classList.remove('onyx-call-active');
                        d.classList.remove('onyx-lobby-hidden');
                     });
                     
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
                    if (clickable) {
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
                }, {passive: false});
            })();
        """.trimIndent()

        webView.evaluateJavascript(js, null)
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onResume() {
        super.onResume()
        injectFilters()
    }
}
