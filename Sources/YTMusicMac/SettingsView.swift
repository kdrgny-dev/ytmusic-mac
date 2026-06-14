import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            interfaceTab.tabItem { Label("Interface", systemImage: "rectangle.3.group") }
        }
        .frame(width: 460, height: 260)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Notify on track change", isOn: $prefs.notifyOnTrackChange)
                Toggle("Mini player always on top", isOn: $prefs.miniPlayerAlwaysOnTop)
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceTab: some View {
        Form {
            Section("YouTube Music tweaks") {
                Toggle("Spotify-like player layout (info left, transport center)",
                       isOn: $prefs.applyPlayerLayout)
                Toggle("Hide Premium promo banners", isOn: $prefs.hidePromos)
            }
            Section {
                Text("Changes apply immediately. If something looks off, use Controls → Reload.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
