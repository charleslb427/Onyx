package com.onyx.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.webkit.*
import android.widget.PopupMenu
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.preference.PreferenceManager
import com.onyx.app.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var webView: WebView
    
    // Permission request for WebRTC (camera/mic)
    private var permissionRequest: PermissionRequest? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.entries.all { it.value }
        if (allGranted) {
            permissionRequest?.grant(permissionRequest?.resources)
        } else {
            permissionRequest?.deny()
            Toast.makeText(this, "Permissions requises pour les appels", Toast.LENGTH_SHORT).show()
        }
        permissionRequest = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        // Remove default ActionBar if present (theme should handle it but just in case)
        supportActionBar?.hide()

        setupNotifications()
        setupWebView()
        setupSwipeRefresh()
        setupFab()
        
        // Check if opened from notification
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        intent?.let { handleIntent(it) }
    }

    private fun handleIntent(intent: Intent) {
        val targetUrl = intent.getStringExtra("target_url")
        if (targetUrl != null) {
            webView.loadUrl(targetUrl)
        } else if (webView.url == null) {
             webView.loadUrl("https://www.instagram.com/")
        }
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
            // Direct access to settings, seamless experience
            startActivity(Intent(this, SettingsActivity::class.java))
        }
    }

    // Menu logic removed as requested (simplified UX)

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            
            val messageChannel = NotificationChannel(
                "onyx_messages",
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Messages Instagram via Onyx"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(messageChannel)
            
            val callChannel = NotificationChannel(
                "onyx_calls",
                getString(R.string.notification_channel_calls),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Appels Instagram via Onyx"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(callChannel)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) 
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    1001
                )
            }
        }
    }

    private fun checkNotificationListenerPermission() {
        val componentName = ComponentName(this, InstagramNotificationListener::class.java)
        val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(this)
        
        if (!enabledListeners.contains(packageName)) {
            // First run? We could show a dialog, but let's be less intrusive and let user find it in settings
            // Or show a small snackbar/toast if needed. Use SettingsActivity to toggle.
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView = binding.webView

        // 🚀 PERFORMANCE OPTIMIZATIONS
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null) // Force Hardware Acceleration
        
        // Enable Third Party Cookies (Crucial for Instagram's auth & caching)
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            
            // ⚡ Cache & Network
            cacheMode = WebSettings.LOAD_DEFAULT 
            // We use LOAD_DEFAULT so it uses network when needed but cache when available.
            // Avoid LOAD_CACHE_ELSE_NETWORK as it might break dynamic feeds.
            
            // Viewport & Zoom
            loadWithOverviewMode = true
            useWideViewPort = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            
            // 📱 Mobile Interactions
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = false
            javaScriptCanOpenWindowsAutomatically = true
                        // Smooth Rendering
            setRenderPriority(WebSettings.RenderPriority.HIGH)
        }

        // Optimize Scrollbar
        webView.isVerticalScrollBarEnabled = false // Hide scrollbar for cleaner look
        webView.isHorizontalScrollBarEnabled = false
        
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                // Only show progress bar if it's a significant load, not just navigation
                binding.progressBar.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                binding.progressBar.visibility = View.GONE
                binding.swipeRefresh.isRefreshing = false
                injectFilters()
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                
                if (isReelsBlocked() && url.contains("/reels/")) {
                    view?.loadUrl("https://www.instagram.com/")
                    return true
                }
                
                if (url.contains("instagram.com")) {
                    // Let WebView handle it (seamless transition)
                    return false
                }
                
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                } catch (e: Exception) { }
                return true
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.let { req ->
                    val resources = req.resources
                    val neededPermissions = mutableListOf<String>()
                    
                    for (resource in resources) {
                        when (resource) {
                            PermissionRequest.RESOURCE_VIDEO_CAPTURE -> {
                                if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.CAMERA)
                                    != PackageManager.PERMISSION_GRANTED) {
                                    neededPermissions.add(Manifest.permission.CAMERA)
                                }
                            }
                            PermissionRequest.RESOURCE_AUDIO_CAPTURE -> {
                                if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.RECORD_AUDIO)
                                    != PackageManager.PERMISSION_GRANTED) {
                                    neededPermissions.add(Manifest.permission.RECORD_AUDIO)
                                }
                            }
                        }
                    }
                    
                    if (neededPermissions.isEmpty()) {
                        req.grant(resources)
                    } else {
                        permissionRequest = req
                        permissionLauncher.launch(neededPermissions.toTypedArray())
                    }
                }
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                if (newProgress == 100) {
                    binding.progressBar.visibility = View.GONE
                    binding.swipeRefresh.isRefreshing = false
                }
            }
        }
    }

    private fun injectFilters() {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        val hideReels = prefs.getBoolean("hide_reels", true)
        val hideExplore = prefs.getBoolean("hide_explore", true)
        val hideAds = prefs.getBoolean("hide_ads", true)

        val isMessages = webView.url?.contains("/direct") == true
        if (isMessages) return

        val cssRules = StringBuilder()
        
        if (hideReels) {
            cssRules.append("a[href*=\"/reels/\"]{display:none!important;}")
            cssRules.append("div[style*=\"reels\"]{display:none!important;}")
            cssRules.append("svg[aria-label*=\"Reels\"]{display:none!important;}")
            cssRules.append("a[href=\"/reels/\"]{display:none!important;}")
            // Hide the Reels tab container specifically
            cssRules.append("div:has(> a[href*=\"/reels/\"]){display:none!important;}")
        }
        
        if (hideExplore) {
            cssRules.append("a[href=\"/explore/\"]{display:none!important;}")
            cssRules.append("a[href*=\"/explore\"]{display:none!important;}")
             // Hide Explore tab container
            cssRules.append("div:has(> a[href*=\"/explore/\"]){display:none!important;}")
        }
        
        // RE-LAYOUT NAVIGATION BAR
        // Force the bottom navigation bar to distribute remaining items evenly
        cssRules.append("div[role=\"tablist\"]{justify-content: space-evenly !important;}")
        cssRules.append("div:has(> a[href=\"/\"]){justify-content: space-evenly !important;}")

        if (hideAds) {
            cssRules.append("article:has(span[class*=\"sponsored\"]){display:none!important;}")
            cssRules.append("article:has(span:contains(\"Sponsorisé\")){display:none!important;}")
            cssRules.append("article:has(span:contains(\"Sponsored\")){display:none!important;}")
        }

        // NO NAGS - Hide "Get the App" banners aggressively
        cssRules.append("div[role=\"banner\"]{display:none!important;}")
        cssRules.append("div:has(a[href*=\"play.google.com\"]){display:none!important;}")
        cssRules.append("div:has(button):has(div:contains(\"Instagram\")){display:none!important;}") // Generic app upsell banner
        cssRules.append("div:has(button:contains(\"Ouvrir\")){display:none!important;}")
        cssRules.append("div:has(button:contains(\"Open\")){display:none!important;}")
        cssRules.append("div:has(button:contains(\"Installer\")){display:none!important;}")
        cssRules.append("div:has(button:contains(\"Install\")){display:none!important;}")
        
        // Hide "Use the App" footer often found on mobile web
        cssRules.append("footer:has(a[href*=\"play.google.com\"]){display:none!important;}")

        val js = """
            (function() {
                var styleId = 'onyx-style';
                var existing = document.getElementById(styleId);
                if (existing) existing.remove();
                
                var style = document.createElement('style');
                style.id = styleId;
                style.textContent = `$cssRules`;
                document.head.appendChild(style);
                
                if (!window.onyxObserver) {
                    window.onyxObserver = new MutationObserver(function() {
                        var style = document.getElementById(styleId);
                        if (!style) {
                            style = document.createElement('style');
                            style.id = styleId;
                            style.textContent = `$cssRules`;
                            document.head.appendChild(style);
                        }
                    });
                    window.onyxObserver.observe(document.body, { childList: true, subtree: true });
                }
            })();
        """.trimIndent()

        webView.evaluateJavascript(js, null)
    }

    private fun isReelsBlocked(): Boolean {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        return prefs.getBoolean("hide_reels", true)
    }

    @Deprecated("Deprecated in Java")
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
