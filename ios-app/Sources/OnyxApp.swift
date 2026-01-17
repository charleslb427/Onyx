
import SwiftUI

@main
struct OnyxApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: "https://www.instagram.com/")!)
                .ignoresSafeArea(edges: .bottom) // Keep status bar visible but extend bottom
                .statusBar(hidden: false)
        }
    }
}
