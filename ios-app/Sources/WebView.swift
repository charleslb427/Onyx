
import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        // Configuration
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        
        // CSS INJECTION LOGIC
        let css = """
            /* ONYX FILTERS */
            /* Hide Reels */
            a[href*="/reels/"], div[style*="reels"], svg[aria-label*="Reels"], a[href="/reels/"] { display: none !important; }
            div:has(> a[href*="/reels/"]) { display: none !important; }
            
            /* Hide Explore */
            a[href="/explore/"], a[href*="/explore"] { display: none !important; }
            div:has(> a[href*="/explore/"]) { display: none !important; }
            
            /* Hide Ads */
            article:has(span[class*="sponsored"]), article:has(span:contains("Sponsorisé")), article:has(span:contains("Sponsored")) { display: none !important; }

            /* Re-layout Navigation Bar (Space Evenly) */
            div[role="tablist"], div:has(> a[href="/"]) { justify-content: space-evenly !important; }

            /* NO NAGS / Banners */
            div[role="banner"] { display: none !important; }
            div:has(a[href*="play.google.com"]) { display: none !important; }
            div:has(a[href*="apps.apple.com"]) { display: none !important; }
            div:has(button:contains("Ouvrir")), div:has(button:contains("Open")), div:has(button:contains("Installer")), div:has(button:contains("Install")) { display: none !important; }
            footer:has(a[href*="apps.apple.com"]) { display: none !important; }
        """
        
        let jsValues = """
            var style = document.createElement('style');
            style.textContent = `\(css)`;
            document.head.appendChild(style);
            
            // Observer to keep re-applying if Instagram removes it
            new MutationObserver(function() {
                if (!document.getElementById('onyx-style')) {
                   style.id = 'onyx-style';
                   if(!style.parentNode) document.head.appendChild(style);
                }
            }).observe(document.body, { childList: true, subtree: true });
        """
        
        let userScript = WKUserScript(source: jsValues, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // User Agent to ensure mobile version
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        // Block Reels URLs if clicked
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let urlStr = navigationAction.request.url?.absoluteString {
                if urlStr.contains("/reels/") {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
