import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            interfaceTab.tabItem { Label("Interface", systemImage: "rectangle.3.group") }
        }
        .frame(width: 520, height: 440)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Notify on track change", isOn: $prefs.notifyOnTrackChange)
                Toggle("Mini player always on top", isOn: $prefs.miniPlayerAlwaysOnTop)
            }
            Section("Playback") {
                Toggle("Always shuffle (re-enables shuffle whenever YT Music turns it off)",
                       isOn: $prefs.alwaysShuffle)
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceTab: some View {
        Form {
            Section("Theme") {
                Picker("Color theme", selection: $prefs.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
            Section("YouTube Music tweaks") {
                Toggle("Spotify-like player layout (info left, transport center)",
                       isOn: $prefs.applyPlayerLayout)
                Toggle("Compact mode (narrow sidebar, tighter rows)",
                       isOn: $prefs.compactMode)
                Toggle("Stacked playlist header (Spotify-style)",
                       isOn: $prefs.stackedHeader)
                Toggle("Zebra striping on track lists", isOn: $prefs.zebraStriping)
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
