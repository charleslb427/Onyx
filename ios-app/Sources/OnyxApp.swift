
import SwiftUI

@main
struct OnyxApp: App {
    @State private var showSettings = false
    // A key to force refresh when coming back from settings
    @State private var refreshTrigger = UUID()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottomTrailing) {
                
                // MAIN WEBVIEW
                WebViewWrapper(refreshTrigger: $refreshTrigger)
                    .edgesIgnoringSafeArea(.bottom)
                
                // SETTINGS FAB (Floating Action Button)
                Button(action: {
                    showSettings = true
                }) {
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
                .padding(.bottom, 80) // Positioned above bottom nav bar area
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                // When settings close, we trigger a refresh to apply new CSS filters
                refreshTrigger = UUID()
            }) {
                SettingsView()
            }
        }
    }
}

// Helper for glassmorphism background on button
struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}
