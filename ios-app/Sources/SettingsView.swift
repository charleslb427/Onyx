
import SwiftUI

struct SettingsView: View {
    @AppStorage("hideReels") private var hideReels = true
    @AppStorage("hideExplore") private var hideExplore = true
    @AppStorage("hideAds") private var hideAds = true
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Filtres")) {
                    Toggle("Masquer les Reels", isOn: $hideReels)
                    Toggle("Masquer Explorer", isOn: $hideExplore)
                    Toggle("Masquer les Publicités", isOn: $hideAds)
                }
                
                Section(footer: Text("Onyx pour iOS 1.0\nInstagram sans distractions.")) {
                    // Footer info
                }
            }
            .navigationTitle("Paramètres")
            .navigationBarItems(trailing: Button("Terminé") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
