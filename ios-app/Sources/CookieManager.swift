
import Foundation
import WebKit

class CookieManager {
    static let shared = CookieManager()
    private let cookiesKey = "instagram_cookies"
    
    private init() {}
    
    // SAVE cookies to UserDefaults
    func saveCookies(completion: @escaping () -> Void = {}) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let cookieData = cookies.compactMap { cookie -> [String: Any]? in
                return [
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path,
                    "isSecure": cookie.isSecure,
                    "isHTTPOnly": cookie.isHTTPOnly,
                    "expiresDate": cookie.expiresDate?.timeIntervalSince1970 ?? 0
                ]
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: cookieData) {
                UserDefaults.standard.set(data, forKey: self.cookiesKey)
                print("🍪 Saved \(cookies.count) cookies")
            }
            completion()
        }
    }
    
    // RESTORE cookies from UserDefaults
    func restoreCookies(completion: @escaping () -> Void = {}) {
        guard let data = UserDefaults.standard.data(forKey: cookiesKey),
              let cookieData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🍪 No saved cookies found")
            completion()
            return
        }
        
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        
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
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("🍪 Restored cookies")
            completion()
        }
    }
}
