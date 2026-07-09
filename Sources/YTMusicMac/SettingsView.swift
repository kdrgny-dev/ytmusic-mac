import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("Genel", systemImage: "gear") }
            interfaceTab.tabItem { Label("Arayüz", systemImage: "rectangle.3.group") }
        }
        .frame(width: 520, height: 440)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Parça değişince bildir", isOn: $prefs.notifyOnTrackChange)
                Toggle("Mini oynatıcı her zaman üstte", isOn: $prefs.miniPlayerAlwaysOnTop)
            }
            Section("Oynatma") {
                Toggle("Her zaman karıştır (YT Music kapattığında yeniden açar)",
                       isOn: $prefs.alwaysShuffle)
                Toggle("Çapraz geçiş (biten şarkıyı kıs, sonrakini aç)",
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
            Section("Performans") {
                Toggle("30 dk duraklatınca yeniden yükle (belleği boşaltır; oturumun açık kalır)",
                       isOn: $prefs.autoReloadOnIdle)
            }
            Section("Yerel arayüz") {
                Toggle("Yerel arayüz modu (YT'nin web arayüzünü SwiftUI kabuğuyla değiştirir)",
                       isOn: $prefs.nativeUIMode)
                Text("Tam yerel kabuk: kitaplık, ana sayfa, keşfet + listeler, çalma listesi/albüm/sanatçı sayfaları, arama, kuyruk ve şarkı sözü panelleri, temalar. WebView altta ses motoru olarak çalışmaya devam eder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceTab: some View {
        Form {
            Section("Tema") {
                Picker("Renk teması", selection: $prefs.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text("\(theme.displayName)\(theme.variantSuffix)").tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Text("Tema anında uygulanır. Bir şey ters görünürse Denetimler → Yeniden Yükle.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
