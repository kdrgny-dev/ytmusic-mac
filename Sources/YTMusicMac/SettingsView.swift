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
                Toggle("Crossfade (fade out the ending track, fade in the next)",
                       isOn: $prefs.crossfadeEnabled)
                if prefs.crossfadeEnabled {
                    HStack {
                        Text("Fade süresi")
                        Slider(value: $prefs.crossfadeDuration, in: 1...12, step: 1)
                        Text("\(Int(prefs.crossfadeDuration)) sn")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("Gerçek Spotify usulü üst üste binme YT'nin tek ses motorunda mümkün değil; bunun yerine biten şarkının sonu kısılır, yeni şarkının başı açılır.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section("Performance") {
                Toggle("Auto-reload after 30 min paused (frees memory; you stay signed in)",
                       isOn: $prefs.autoReloadOnIdle)
            }
            Section("Native UI") {
                Toggle("Native UI mode (replaces YT's web UI with a SwiftUI shell)",
                       isOn: $prefs.nativeUIMode)
                Text("Full native shell: library, home, explore + charts, playlist/album/artist pages, search, queue & lyrics panels, themes. The WebView stays alive underneath as the audio engine.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceTab: some View {
        Form {
            Section("Theme") {
                Picker("Color theme", selection: $prefs.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text("\(theme.displayName)\(theme.variantSuffix)").tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Text("Theme uygulanır uygulanmaz değişir. Bir şey ters görünürse Controls → Reload.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
