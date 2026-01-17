
import SwiftUI
import UserNotifications

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
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(Color.primary)
                        .padding(12)
                        .background(VisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
            .sheet(isPresented: $showSettings, onDismiss: { refreshTrigger = UUID() }) {
                SettingsView()
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Request Notification Permission
        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
        
        application.registerForRemoteNotifications()
        return true
    }
    
    // Called when a notification arrives while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    // Successful Registration (Token received)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        // In a real app, send this token to your server.
        // For Web Push, the WebView handles the service worker registration internally if allowed.
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register: \(error)")
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}
