
import SwiftUI
import UserNotifications
import BackgroundTasks
import WebKit

@main
struct OnyxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showSettings = false
    @State private var refreshTrigger = UUID()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottomTrailing) {
                WebViewWrapper(refreshTrigger: $refreshTrigger)
                    .edgesIgnoringSafeArea(.bottom)
                
                // DISCRETE SETTINGS BUTTON (Ghost Mode)
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .frame(width: 20, height: 20) // Smaller
                        .foregroundColor(Color.primary.opacity(0.3)) // Very transparent (Ghost)
                        .padding(12)
                        .background(Color.clear) // No background logic, just the icon
                        .contentShape(Rectangle()) // Hit area
                }
                .padding(.trailing, 16)
                .padding(.bottom, 60) // Just above the nav bar
            }
            .sheet(isPresented: $showSettings, onDismiss: { refreshTrigger = UUID() }) {
                SettingsView()
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    static var shared: AppDelegate!
    let webViewProcessPool = WKProcessPool()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        AppDelegate.shared = self
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        
        UserDefaults.standard.register(defaults: [
            "hideReels": true,
            "hideExplore": true,
            "hideAds": true
        ])
        
        // ✅ RESTORE COOKIES ON LAUNCH
        CookieManager.shared.restoreCookies()
        
        // ✅ OBSERVE BACKGROUND/TERMINATE TO SAVE COOKIES (More reliable in SwiftUI)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            CookieManager.shared.saveCookies()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            CookieManager.shared.saveCookies()
        }
        // Also save when app becomes inactive (user switches apps)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            CookieManager.shared.saveCookies()
        }
        
        WebSocketManager.shared.connect()
        
        return true
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
