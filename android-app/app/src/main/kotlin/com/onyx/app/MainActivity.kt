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
    
    // Hold the WebView permission request while asking user
    private var pendingPermissionRequest: PermissionRequest? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            // User granted Android permissions -> Grant WebView permissions
            pendingPermissionRequest?.let { request ->
                request.grant(request.resources)
                pendingPermissionRequest = null
            }
        } else {
            // User denied -> Deny WebView
            pendingPermissionRequest?.deny()
            pendingPermissionRequest = null
            Toast.makeText(this, "Permissions requises pour les appels", Toast.LENGTH_SHORT).show()
        }
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
                binding.progressBar.visibility = View.VISIBLE
                // Inject immediately to catch early renders
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
                // We do NOT block explore URL anymore, we handle it via CSS to allow search
                // val hideExplore = prefs.getBoolean("hide_explore", true) 
                
                // 1. BLOCK REELS FEED (Infinite Scroll) but ALLOW specific Reels (DMs/Saved)
                if (hideReels) {
                    // Block ONLY the main feed entry point
                    if (url == "https://www.instagram.com/reels/" || url.contains("/reels/audio/")) {
                         return true // Block
                    }
                }
                
                // 2. SMART SKIP: If we somehow end up on a blocked page (e.g. via history back), go Home
                // (Note: shouldOverrideUrlLoading catches new navigations, for history we rely on onPageFinished check or just let it load empty)

                if (url.contains("instagram.com")) {
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
                if (request == null) return
                
                val resources = request.resources
                val androidPermissions = mutableListOf<String>()
                
                if (resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                    androidPermissions.add(Manifest.permission.CAMERA)
                }
                if (resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) {
                    androidPermissions.add(Manifest.permission.RECORD_AUDIO)
                    androidPermissions.add(Manifest.permission.MODIFY_AUDIO_SETTINGS)
                }

                val missingPermissions = androidPermissions.filter {
                    ContextCompat.checkSelfPermission(this@MainActivity, it) != PackageManager.PERMISSION_GRANTED
                }

                if (missingPermissions.isEmpty()) {
                    request.grant(resources)
                } else {
                    pendingPermissionRequest = request
                    permissionLauncher.launch(missingPermissions.toTypedArray())
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest?) {
                if (pendingPermissionRequest == request) {
                    pendingPermissionRequest = null
                }
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                if (newProgress > 10) injectFilters()
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

        val cssRules = StringBuilder()
        
        if (hideReels) {
            // 1. Hide Reels Tab Button
            cssRules.append("a[href='/reels/'], a[href*='/reels/'][role='link'] { display: none !important; } ")
            // 2. Hide "Reels" section in Profile
            cssRules.append("a[href*='/reels/'] { display: none !important; } ") 
            // 3. Anti-Doomscroll (disable scroll on Reel pages if possible)
            cssRules.append("div[style*='overflow-y: scroll'] > div > div > div[role='button'] { pointer-events: none !important; } ")
        }
        
        if (hideExplore) {
            // 1. STRICT BLOCKING of Feed Items (Posts & Reels)
            cssRules.append("main[role='main'] a[href^='/p/'], main[role='main'] a[href^='/reel/'] { display: none !important; } ")
            // 2. Hide Loaders/Spinners
            cssRules.append("svg[aria-label='Chargement...'], svg[aria-label='Loading...'] { display: none !important; } ")
        }
        
        if (hideAds) {
            cssRules.append("article:has(span:contains('Sponsored')), article:has(span:contains('Sponsorisé')) { display: none !important; } ")
        }
        
        // Common cleanup & FORCE SEARCH VISIBILITY
        cssRules.append("input[type='text'], input[placeholder='Rechercher'], input[aria-label='Rechercher'] { display: block !important; opacity: 1 !important; visibility: visible !important; } ")
        cssRules.append("div[role='dialog'] { display: block !important; opacity: 1 !important; visibility: visible !important; } ")
        cssRules.append("a[href^='/name/'], a[href^='/explore/tags/'], a[href^='/explore/locations/'] { display: inline-block !important; opacity: 1 !important; visibility: visible !important; } ")
        
        cssRules.append("div[role='tablist'] { justify-content: space-evenly !important; } div[role='banner'], footer, .AppCTA { display: none !important; }")

        val safeCSS = cssRules.toString().replace("`", "\\`")

        val js = """
            (function() {
                // 1. Inject Style Rule
                var styleId = 'onyx-style';
                var style = document.getElementById(styleId);
                if (!style) {
                    style = document.createElement('style');
                    style.id = styleId;
                    document.head.appendChild(style);
                }
                style.textContent = `$safeCSS`;
                
                // 2. JS Cleanup (Backup for CSS)
                function cleanContent() {
                     ${if (hideExplore) "var loaders = document.querySelectorAll('svg[aria-label=\"Chargement...\"], svg[aria-label=\"Loading...\"]'); loaders.forEach(l => l.style.display = 'none');" else ""}
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
        """.trimIndent()

        webView.evaluateJavascript(js, null)
    }

    private fun isReelsBlocked(): Boolean = PreferenceManager.getDefaultSharedPreferences(this).getBoolean("hide_reels", true)
    private fun isExploreBlocked(): Boolean = PreferenceManager.getDefaultSharedPreferences(this).getBoolean("hide_explore", true)


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
