import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label(L10n.t("settings.tab.general"), systemImage: "gear") }
            interfaceTab.tabItem { Label(L10n.t("settings.tab.interface"), systemImage: "rectangle.3.group") }
        }
        .frame(width: 520, height: 480)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(L10n.t("settings.notifyOnTrackChange"), isOn: $prefs.notifyOnTrackChange)
                Toggle(L10n.t("settings.miniAlwaysOnTop"), isOn: $prefs.miniPlayerAlwaysOnTop)
            }
            Section(L10n.t("settings.section.playback")) {
                Toggle(L10n.t("settings.alwaysShuffle"), isOn: $prefs.alwaysShuffle)
                Toggle(L10n.t("settings.crossfade"), isOn: $prefs.crossfadeEnabled)
                if prefs.crossfadeEnabled {
                    HStack {
                        Text(L10n.t("settings.fadeDuration"))
                        Slider(value: $prefs.crossfadeDuration, in: 1...12, step: 1)
                        Text(L10n.t("settings.seconds", Int(prefs.crossfadeDuration)))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text(L10n.t("settings.crossfade.caption"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section(L10n.t("settings.section.performance")) {
                Toggle(L10n.t("settings.autoReloadOnIdle"), isOn: $prefs.autoReloadOnIdle)
            }
            Section(L10n.t("settings.section.history")) {
                Toggle(L10n.t("settings.historyEnabled"), isOn: $prefs.historyEnabled)
                Text(L10n.t("settings.history.caption"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section(L10n.t("settings.section.nativeUI")) {
                Toggle(L10n.t("settings.nativeUIMode"), isOn: $prefs.nativeUIMode)
                Text(L10n.t("settings.nativeUI.caption"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceTab: some View {
        Form {
            Section(L10n.t("settings.section.language")) {
                Picker(L10n.t("settings.language"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.menu)

                Picker(L10n.t("settings.region"), selection: $prefs.region) {
                    ForEach(AppRegion.allCases) { region in
                        Text(region.label(in: prefs.language.resolved)).tag(region)
                    }
                }
                .pickerStyle(.menu)

                Text(L10n.t("settings.region.caption"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section(L10n.t("settings.section.theme")) {
                Picker(L10n.t("settings.colorTheme"), selection: $prefs.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text("\(theme.displayName)\(theme.variantSuffix)").tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Text(L10n.t("settings.theme.caption"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
