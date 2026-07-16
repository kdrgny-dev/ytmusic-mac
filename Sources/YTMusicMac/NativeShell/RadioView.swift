import SwiftUI

/// The radio page: endless stations seeded from the local play history, YT's
/// own mixes, and the mood/genre chips. Colors come from `.primary` /
/// `prefs.theme` so light themes work without overriding colorScheme.
struct RadioView: View {
    @ObservedObject var vm: NativeShellViewModel
    @ObservedObject private var prefs = Preferences.shared

    private var isEmpty: Bool { vm.radioSections.isEmpty && vm.genreSections.isEmpty }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                header
                if vm.radioLoading && isEmpty {
                    HomeExploreSkeleton(rows: 3)
                } else if let msg = vm.radioError, isEmpty {
                    errorState(msg)
                } else {
                    // Not an error: the genre rows below still work, there's
                    // just no history to build personal stations from yet.
                    if vm.radioNeedsHistory { needsHistoryNote }
                    ForEach(vm.radioSections) { section in
                        RadioSectionRow(section: section, vm: vm)
                    }
                    ForEach(vm.genreSections) { section in
                        GenreCarousel(section: section, vm: vm)
                    }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("shell.radio.kindLabel"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(L10n.t("shell.radio.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.t("shell.radio.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            Spacer()
            Button(action: { vm.reloadRadio() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("shell.action.refresh"))
        }
    }

    // MARK: - Zero states

    /// Recording being off and history being merely thin both empty the
    /// personal sections, but only one of them is waiting on time passing —
    /// promising stations that can never arrive would be a lie.
    @ViewBuilder private var needsHistoryNote: some View {
        if prefs.historyEnabled {
            note(icon: "waveform",
                 title: L10n.t("shell.radio.needsHistory.title"),
                 caption: L10n.t("shell.radio.needsHistory.caption"))
        } else {
            note(icon: "eye.slash",
                 title: L10n.t("shell.radio.historyOff.title"),
                 caption: L10n.t("shell.radio.historyOff.caption"))
        }
    }

    private func note(icon: String, title: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary.opacity(0.4))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.primary.opacity(0.4))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.6))
            Button(L10n.t("common.retry")) { vm.reloadRadio() }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

// MARK: - Section row

/// One radio row. A section carries either stations (ours, seeded from local
/// history) or YT's own mix cards, never both.
private struct RadioSectionRow: View {
    let section: NativeShellViewModel.RadioSection
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        if !section.stations.isEmpty {
            CarouselSection(
                title: section.title,
                subtitle: nil,
                caption: section.subtitle,
                items: section.stations,
                pageSize: 3,
                estimatedItemWidth: 162
            ) { station in
                Button(action: { vm.startRadio(station) }) {
                    RadioStationTile(station: station, onPlay: { vm.startRadio(station) })
                }
                .buttonStyle(.plain)
                .contextMenu { radioStationContextMenu(station, vm) }
            }
        } else {
            CarouselSection(
                title: section.title,
                subtitle: nil,
                caption: section.subtitle,
                items: section.cards,
                pageSize: 3,
                estimatedItemWidth: 162
            ) { card in
                Button(action: { vm.playHomeCard(card) }) {
                    HomeCardView(card: card, onPlay: { vm.playHomeCard(card) })
                }
                .buttonStyle(.plain)
                .contextMenu { homeCardContextMenu(card, vm) }
            }
        }
    }
}

// MARK: - Station tile

/// A station tile. Mirrors HomeCardView's 150×150 cover and hover play FAB,
/// but wears a radio badge: a station titled "Song — Artist" is otherwise
/// indistinguishable from a plain song card, and it does something very
/// different when clicked.
struct RadioStationTile: View {
    let station: RadioStation
    var onPlay: (() -> Void)? = nil
    @State private var hovered: Bool = false
    @ObservedObject private var prefs = Preferences.shared

    private var coverShape: AnyShape {
        station.kind == .artist
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var placeholderIcon: String {
        switch station.kind {
        case .artist:    return "person.fill"
        case .discovery: return "sparkles"
        case .track:     return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .frame(width: 150, height: 150)
                .clipShape(coverShape)
                .overlay(
                    coverShape.stroke(Color.primary.opacity(hovered ? 0.18 : 0), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if hovered, let onPlay {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(prefs.theme.accentColor))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                }
                .scaleEffect(hovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(hovered ? 0.5 : 0.0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: hovered)
            VStack(alignment: .leading, spacing: 3) {
                badge
                Text(station.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(station.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    /// Sits under the cover rather than in a corner of it: artist covers are
    /// circular, and a corner badge would float in the clipped-away space.
    private var badge: some View {
        HStack(spacing: 3) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 8, weight: .bold))
            Text(L10n.t("shell.radio.badge").uppercased(with: L10n.locale))
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
        }
        .foregroundColor(prefs.theme.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(prefs.theme.accentColor.opacity(0.15)))
    }

    @ViewBuilder
    private var cover: some View {
        if let s = station.artworkURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: coverPlaceholder
                }
            }
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: placeholderIcon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.primary.opacity(0.3))
        }
    }
}

// MARK: - Station context menu

@MainActor @ViewBuilder
func radioStationContextMenu(_ station: RadioStation,
                             _ vm: NativeShellViewModel) -> some View {
    Button { vm.startRadio(station) } label: {
        Label(L10n.t("shell.action.startRadio"), systemImage: "dot.radiowaves.left.and.right")
    }
    Button { vm.playTrack(seedTrack(station)) } label: {
        Label(L10n.t("shell.radio.playSeed"), systemImage: "music.note")
    }
}

/// The station's seed as a plain track. An artist station is titled after the
/// artist, not after its seed song, so only the artist carries over — the
/// player fills the real title in once it starts.
@MainActor
private func seedTrack(_ station: RadioStation) -> NativeShellViewModel.TrackSummary {
    let isArtist = station.kind == .artist
    return NativeShellViewModel.TrackSummary(id: station.seedVideoId,
                                             title: isArtist ? "" : station.title,
                                             artist: isArtist ? station.title : station.subtitle,
                                             duration: nil,
                                             thumbnailURL: station.artworkURL)
}
