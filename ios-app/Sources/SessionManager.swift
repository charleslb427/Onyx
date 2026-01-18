
import Foundation
import WebKit

class SessionManager {
    static let shared = SessionManager()
    
    private let userDefaults = UserDefaults.standard
    private let cookiesKey = "instagram_cookies"
    private let localStorageKey = "instagram_localStorage"
    
    private init() {}
    
    // ✅ SAVE COMPLETE SESSION (Cookies + localStorage)
    func saveSession(from webView: WKWebView, completion: @escaping () -> Void = {}) {
        print("💾 Saving session...")
        
        let group = DispatchGroup()
        
        // 1. Save Cookies
        group.enter()
        saveCookies {
            group.leave()
        }
        
        // 2. Save localStorage
        group.enter()
        saveLocalStorage(from: webView) {
            group.leave()
        }
        
        group.notify(queue: .main) {
            print("✅ Session saved completely")
            completion()
        }
    }
    
    // ✅ RESTORE COMPLETE SESSION
    func restoreSession(to webView: WKWebView, completion: @escaping () -> Void) {
        print("🔄 Restoring session...")
        
        // 1. Restore Cookies first
        restoreCookies()
        
        // 2. Restore localStorage (needs page loaded first, will be injected after)
        // We store the data, will inject via JavaScript after page starts loading
        completion()
    }
    
    // Inject localStorage after page starts loading
    func injectLocalStorage(to webView: WKWebView) {
        guard let savedJSON = userDefaults.string(forKey: localStorageKey), !savedJSON.isEmpty, savedJSON != "{}" else {
            print("🍪 No localStorage to restore")
            return
        }
        
        // Escape the JSON for JavaScript injection
        let escapedJSON = savedJSON.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "'", with: "\\'")
        
        let script = """
        (function() {
            try {
                const data = JSON.parse('\(escapedJSON)');
                for (const key in data) {
                    localStorage.setItem(key, data[key]);
                }
                console.log('Onyx: localStorage restored');
            } catch(e) {
                console.log('Onyx: localStorage restore error', e);
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ localStorage injection error: \(error)")
            } else {
                print("✅ localStorage restored")
            }
        }
    }
    
    // --- COOKIES ---
    private func saveCookies(completion: @escaping () -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let instagramCookies = cookies.filter { $0.domain.contains("instagram") }
            
            let cookieData = instagramCookies.compactMap { cookie -> [String: Any]? in
                var props: [String: Any] = [
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path,
                    "isSecure": cookie.isSecure,
                    "isHTTPOnly": cookie.isHTTPOnly
                ]
                if let expires = cookie.expiresDate {
                    props["expiresDate"] = expires.timeIntervalSince1970
                }
                return props
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: cookieData) {
                self.userDefaults.set(data, forKey: self.cookiesKey)
                print("📦 Saved \(instagramCookies.count) cookies")
            }
            completion()
        }
    }
    
    private func restoreCookies() {
        guard let data = userDefaults.data(forKey: cookiesKey),
              let cookieData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🍪 No saved cookies")
            return
        }
        
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        
        for dict in cookieData {
            guard let name = dict["name"] as? String,
                  let value = dict["value"] as? String,
                  let domain = dict["domain"] as? String,
                  let path = dict["path"] as? String else { continue }
            
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]
            
            if let isSecure = dict["isSecure"] as? Bool, isSecure {
                properties[.secure] = true
            }
            if let expires = dict["expiresDate"] as? TimeInterval, expires > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expires)
            }
            
            if let cookie = HTTPCookie(properties: properties) {
                cookieStore.setCookie(cookie)
            }
        }
        print("✅ Restored cookies")
    }
    
    // --- LOCALSTORAGE ---
    private func saveLocalStorage(from webView: WKWebView, completion: @escaping () -> Void) {
        let script = "JSON.stringify(localStorage)"
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let jsonString = result as? String, !jsonString.isEmpty {
                self?.userDefaults.set(jsonString, forKey: self?.localStorageKey ?? "")
                print("💾 localStorage saved")
            }
            completion()
        }
    }
}
