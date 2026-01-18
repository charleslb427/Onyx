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
        
        if (hideReels) {
            cssRules.append("a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; } ")
            cssRules.append("a[href*='/reels/'] { display: none !important; } ") 
            cssRules.append("div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } ")
        }
        
        if (hideExplore) {
            cssRules.append("main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } ")
            cssRules.append("svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } ")
        }
        
        if (hideAds) {
            cssRules.append("article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } ")
        }
        
        // Mobile Layout Force
        cssRules.append("@media (min-width: 0px) { body { --grid-numcols: 1 !important; font-size: 16px !important; } } ")
        cssRules.append("div[role='main'] { max-width: 100% !important; margin: 0 !important; } ")
        cssRules.append("nav[role='navigation'] { width: 100% !important; } ")
        cssRules.append("[class*='sidebar'], [class*='desktop'] { display: none !important; } ")
        
        // 📞 CALL UI MAGIC: Conditional Class
        cssRules.append(".onyx-call-ui { width: 100vw !important; height: 100vh !important; left: 0 !important; top: 0 !important; transform: scale(0.6) !important; transform-origin: top left !important; } ")
        cssRules.append(".onyx-call-ui > div { width: 166% !important; height: 166% !important; } ")
        cssRules.append(".onyx-call-ui div:has(button) { bottom: 20px !important; max-width: 100% !important; flex-wrap: wrap !important; justify-content: center !important; gap: 10px !important; } ")
        cssRules.append(".onyx-call-ui button { transform: scale(1.2); margin: 5px !important; } ")
        
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
                
                function cleanContent() {
                     ${if (hideExplore) "var loaders = document.querySelectorAll('svg[aria-label=\"Chargement...\"], svg[aria-label=\"Loading...\"]'); loaders.forEach(l => l.style.display = 'none');" else ""}
                     
                     // DETECT CALL (Lobby + Active)
                     var dialogs = document.querySelectorAll('div[role="dialog"]');
                     dialogs.forEach(d => {
                        var text = d.innerText || "";
                        var hasMedia = d.querySelector('video') || d.querySelector('audio');
                        var hasCallButtons = d.querySelector('button svg') || d.querySelector('button[aria-label*="Micro"]');
                        var isLobby = text.includes("Rejoindre") || text.includes("Join") || text.includes("Prêt") || text.includes("Ready");
                        
                        var isCall = hasMedia || hasCallButtons || isLobby;
                        var isCookie = text.includes('Cookies') || text.includes('confidentialité');
                        
                        if (isCall && !isCookie) {
                            d.classList.add('onyx-call-ui');
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
