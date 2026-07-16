import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The SwiftUI shell that takes over the main window when Native Mode is on.
/// WebView stays alive underneath as the audio engine but its UI is hidden
/// via CSS — what the user sees is this view, end-to-end.
///
/// Layout: three rows (header + body + player bar), body is two columns
/// (sidebar + main). Tokens follow a near-black palette with slightly
/// lighter surface tints — Apple Music / Spotify / Notion family.
struct NativeShellView: View {
    @EnvironmentObject private var media: MediaController
    @StateObject private var vm = NativeShellViewModel.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updater = UpdateChecker.shared

    // Surface tokens, driven by the selected theme so picking a theme
    // recolors the native shell live (not just the hidden WebView).
    private var bgBase: Color    { prefs.theme.baseColor }     // main content
    private var bgSurface: Color { prefs.theme.surfaceColor }  // player bar / panels
    private var bgRaised: Color  { prefs.theme.raisedColor }   // hover / chips
    private var bgSidebar: Color { prefs.theme.sidebarColor }  // sidebar (distinct region)
    private var strokeColor: Color { prefs.theme.borderColor } // dividers / outlines

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // A broken app outranks a nicer one: errors win the bar.
                if let banner = vm.banner {
                    BannerBar(banner: banner, vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let update = updater.available {
                    UpdateBar(update: update)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                HStack(spacing: 0) {
                    Sidebar(bg: bgSidebar, stroke: strokeColor, vm: vm)
                    Divider().background(strokeColor)
                    MainContent(bg: bgBase, vm: vm)
                    if vm.isQueueVisible {
                        Divider().background(strokeColor)
                        QueuePanel(bg: bgSurface, raised: bgRaised, vm: vm)
                            .transition(.move(edge: .trailing))
                    }
                    if vm.isLyricsVisible {
                        Divider().background(strokeColor)
                        LyricsPanel(bg: bgSurface, vm: vm)
                            .transition(.move(edge: .trailing))
                    }
                    if vm.isThemePickerVisible {
                        Divider().background(strokeColor)
                        ThemePanel(bg: bgSurface, raised: bgRaised, vm: vm)
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(strokeColor)

                PlayerBar(bg: bgSurface, raised: bgRaised, vm: vm)
                    .frame(height: 72)
            }

            if vm.isCreatePlaylistVisible {
                CreatePlaylistOverlay(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
            }

            if vm.similarSeed != nil {
                SimilarPlaylistOverlay(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(33)
            }

            if let target = vm.renameTarget {
                RenamePlaylistOverlay(vm: vm, playlist: target)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(31)
            }

            if let target = vm.deleteTarget {
                DeleteConfirmOverlay(vm: vm, playlist: target)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(32)
            }

            if vm.isNowPlayingVisible {
                NowPlayingScreen(vm: vm)
                    .transition(.move(edge: .bottom))
                    .zIndex(40)
            }

            if vm.clipSurface != .none {
                ClipCrawlScreen(vm: vm)
                    .transition(.opacity)
                    .zIndex(45)
            }

            if let msg = vm.toast {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .environment(\.colorScheme, .dark) // dark HUD on any theme
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.bottom, 88) // above the player bar
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
            }
        }
        .background(bgBase)
        .tint(prefs.theme.accentColor)
        // NSHostingView (AppKit-embedded) ignores .preferredColorScheme — it
        // needs the environment value set directly for .primary/.secondary to
        // adapt on light themes.
        .environment(\.colorScheme, prefs.theme.isDark ? .dark : .light)
        .preferredColorScheme(prefs.theme.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.18), value: vm.isQueueVisible)
        .animation(.easeInOut(duration: 0.18), value: vm.isLyricsVisible)
        .animation(.easeInOut(duration: 0.18), value: vm.isThemePickerVisible)
        .animation(.easeInOut(duration: 0.28), value: vm.isNowPlayingVisible)
        .animation(.easeInOut(duration: 0.22), value: vm.clipSurface)
        .animation(.easeInOut(duration: 0.18), value: vm.isCreatePlaylistVisible)
        // Without this the overlay's .transition has no animation scope to run
        // in and gets stuck half-dismissed — a translucent film over the page.
        .animation(.easeInOut(duration: 0.18), value: vm.similarSeed)
        .animation(.easeInOut(duration: 0.18), value: vm.renameTarget)
        .animation(.easeInOut(duration: 0.18), value: vm.deleteTarget)
        .animation(.easeInOut(duration: 0.18), value: prefs.sidebarCollapsed)
        .animation(.easeInOut(duration: 0.2), value: vm.toast)
        .animation(.easeInOut(duration: 0.2), value: vm.banner)
        .onAppear {
            vm.loadPlaylistsIfNeeded()
            // Land users on Home by default so first impression is content,
            // not the "Pick a playlist" placeholder.
            vm.goHome()
            vm.loadLibraryIfNeeded()
        }
    }
}

// MARK: - Failure banner

/// App-wide breakage (no network, dead session) gets a bar across the top.
/// Page-level "couldn't load this" stays inline where it happened.
private struct BannerBar: View {
    let banner: NativeShellViewModel.Banner
    @ObservedObject var vm: NativeShellViewModel

    private var tint: Color {
        banner == .offline ? .orange : .red
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner == .offline ? "wifi.slash" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
            Text(banner.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            Button(action: { vm.resolveBanner() }) {
                Text(banner.actionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.9))
        .environment(\.colorScheme, .dark)
    }
}

/// New build on the download site. The app is ad-hoc signed, so it can't
/// swap itself out — we open the DMG and let the user drag it over.
private struct UpdateBar: View {
    let update: UpdateChecker.Update
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(L10n.t("shell.update.available", update.version))
                .font(.system(size: 12, weight: .semibold))
            if let notes = update.notes {
                Text(notes)
                    .font(.system(size: 12))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button(action: { NSWorkspace.shared.open(update.downloadURL) }) {
                Text(L10n.t("shell.update.download"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
            Button(action: { UpdateChecker.shared.skip(update) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .help(L10n.t("shell.update.skip"))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(prefs.theme.accentColor.opacity(0.92))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Search overlay

private struct SearchView: View {
    @ObservedObject var vm: NativeShellViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().background(Color.primary.opacity(0.08))
            tabBar
            Divider().background(Color.primary.opacity(0.08))
            resultsArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(NativeShellViewModel.SearchKind.allCases) { kind in
                Button(action: { vm.searchTab = kind }) {
                    Text(kind.label)
                        .font(.system(size: 12, weight: vm.searchTab == kind ? .semibold : .regular))
                        .foregroundColor(vm.searchTab == kind ? .white : .primary.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(vm.searchTab == kind ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.5))
            TextField(L10n.t("shell.search.placeholder"), text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .focused($focused)
                .onSubmit {
                    if let first = vm.searchResults.first { vm.openSearchResult(first) }
                }
            if vm.searchLoading {
                ProgressView().controlSize(.small)
            } else if !vm.searchQuery.isEmpty {
                Button(action: { vm.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if vm.searchQuery.isEmpty {
            if vm.searchHistory.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.primary.opacity(0.25))
                    Text(L10n.t("shell.search.emptyHint", vm.searchTab.label.lowercased()))
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                recentSearches
            }
        } else if let msg = vm.searchError, vm.searchResults.isEmpty, !vm.searchLoading {
            ScrollView {
                VStack(spacing: 4) {
                    if !vm.searchSuggestions.isEmpty { suggestions }
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.5))
                        .padding(.top, 12)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !vm.searchSuggestions.isEmpty { suggestions }
                    ForEach(vm.searchResults) { r in
                        Button(action: { vm.openSearchResult(r) }) {
                            SearchResultRow(result: r,
                                            trackCount: vm.playlistTrackCounts[r.id])
                        }
                        .buttonStyle(.plain)
                        .onAppear { vm.fetchPlaylistTrackCount(for: r) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }

    /// YT's own autocomplete, above the results. Clicking one replaces the
    /// query, which re-runs the search through the normal debounce path.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("shell.search.suggestions"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.primary.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            ForEach(vm.searchSuggestions, id: \.self) { s in
                Button(action: { vm.applyRecentSearch(s); focused = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.4))
                        Text(s)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 10))
                            .foregroundColor(.primary.opacity(0.3))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.vertical, 6)
        }
    }

    private var recentSearches: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.t("shell.search.recent"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(.primary.opacity(0.5))
                    Spacer()
                    Button(L10n.t("shell.action.clear")) { vm.clearSearchHistory() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                ForEach(vm.searchHistory, id: \.self) { q in
                    Button(action: { vm.applyRecentSearch(q); focused = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.4))
                            Text(q)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.3))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }
}

private struct SearchResultRow: View {
    let result: NativeShellViewModel.SearchResult
    /// Song count for playlist rows (nil while loading or for non-playlists).
    var trackCount: Int? = nil
    @State private var hovered: Bool = false

    /// Artists are circular thumbs; everything else is a rounded square.
    private var coverShape: AnyShape {
        result.kind == .artist
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 3))
    }

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 40, height: 40)
                .clipShape(coverShape)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trackCount {
                Text(L10n.plural("shell.songCount", trackCount))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = result.thumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color.primary.opacity(0.06)
                }
            }
        } else {
            Color.primary.opacity(0.06)
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    let bg: Color
    let stroke: Color
    @ObservedObject var vm: NativeShellViewModel
    @ObservedObject private var prefs = Preferences.shared
    @State private var draggedPlaylistId: String?

    private struct TopItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let action: () -> Void
    }

    private var topItems: [TopItem] {
        [
            .init(id: "home",    icon: "house.fill",            label: L10n.t("shell.sidebar.home"),    action: { vm.goHome() }),
            .init(id: "explore", icon: "safari",                label: L10n.t("shell.sidebar.explore"), action: { vm.goExplore() }),
            .init(id: "radio",   icon: "dot.radiowaves.left.and.right", label: L10n.t("shell.sidebar.radio"), action: { vm.goRadio() }),
            .init(id: "search",  icon: "magnifyingglass",       label: L10n.t("shell.sidebar.search"),  action: { vm.goSearch() }),
            .init(id: "history", icon: "clock.arrow.circlepath", label: L10n.t("shell.sidebar.history"), action: { vm.goHistory() }),
            .init(id: "statistics", icon: "chart.bar.fill", label: L10n.t("shell.sidebar.statistics"), action: { vm.goStatistics() })
        ]
    }

    var body: some View {
        Group {
            if prefs.sidebarCollapsed { collapsedBody } else { expandedBody }
        }
        .frame(width: prefs.sidebarCollapsed ? 72 : 240)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                collapseToggle
                Spacer()
                createButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader(L10n.t("shell.sidebar.section.browse"))
                    ForEach(topItems) { item in
                        Button(action: item.action) {
                            sidebarRow(icon: item.icon, label: item.label, active: isTopActive(item.id))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        sectionHeader(L10n.t("shell.sidebar.yourPlaylists"))
                        Spacer()
                        Button(action: { vm.reload() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                    .padding(.top, 18)

                    playlistSection

                    if !vm.followedArtists.isEmpty {
                        sectionHeader(L10n.t("shell.sidebar.artists")).padding(.top, 18)
                        ForEach(vm.followedArtists) { a in
                            Button(action: { vm.openArtist(browseId: a.id, name: a.title) }) {
                                playlistRow(a, circular: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !vm.savedAlbums.isEmpty {
                        sectionHeader(L10n.t("shell.sidebar.albums")).padding(.top, 18)
                        ForEach(vm.savedAlbums) { al in
                            Button(action: { vm.openPlaylist(al) }) {
                                playlistRow(al, active: isPlaylistActive(al))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: Collapsed (icon rail)

    private var collapsedBody: some View {
        VStack(spacing: 10) {
            collapseToggle
            createButton
            Divider().background(stroke).padding(.horizontal, 14)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(topItems) { item in
                        Button(action: item.action) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14))
                                .foregroundColor(.primary.opacity(0.7))
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.label)
                    }
                    Divider().background(stroke).padding(.horizontal, 14)
                    ForEach(vm.orderedPlaylists) { p in
                        Button(action: { vm.openPlaylist(p) }) {
                            thumbnail(for: p)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(prefs.theme.accentColor,
                                                      lineWidth: vm.isNowPlayingCollection(p) ? 2 : 0)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(draggedPlaylistId == p.id ? 0.4 : 1)
                        .onDrag {
                            draggedPlaylistId = p.id
                            return NSItemProvider(object: p.id as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: PlaylistDropDelegate(targetId: p.id, vm: vm,
                                                               draggedId: $draggedPlaylistId))
                        .help(vm.isNowPlayingCollection(p)
                              ? L10n.t("shell.sidebar.nowPlayingFrom", p.title)
                              : p.title)
                        .contextMenu { playlistContextMenu(p) }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 12)
    }

    private var collapseToggle: some View {
        Button(action: { prefs.sidebarCollapsed.toggle() }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.t(prefs.sidebarCollapsed ? "shell.sidebar.expand" : "shell.sidebar.collapse"))
    }

    private var createButton: some View {
        Button(action: { vm.beginCreatePlaylist() }) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.playlist.new"))
    }

    @ViewBuilder
    private var playlistSection: some View {
        if vm.loadingPlaylists && vm.playlists.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text(L10n.t("shell.loading"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        } else if let msg = vm.errorMessage, vm.playlists.isEmpty {
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .lineLimit(3)
        } else {
            ForEach(vm.orderedPlaylists) { p in
                Button(action: { vm.openPlaylist(p) }) {
                    playlistRow(p, active: isPlaylistActive(p))
                }
                .buttonStyle(.plain)
                .opacity(draggedPlaylistId == p.id ? 0.4 : 1)
                .onDrag {
                    draggedPlaylistId = p.id
                    return NSItemProvider(object: p.id as NSString)
                }
                .onDrop(of: [UTType.text],
                        delegate: PlaylistDropDelegate(targetId: p.id, vm: vm,
                                                       draggedId: $draggedPlaylistId))
                .contextMenu { playlistContextMenu(p) }
            }
        }
    }

    @ViewBuilder
    private func playlistContextMenu(_ p: NativeShellViewModel.PlaylistSummary) -> some View {
        Button { vm.openPlaylist(p) } label: { Label(L10n.t("common.open"), systemImage: "arrow.right.circle") }
        if vm.isEditablePlaylist(p) {
            Button { vm.beginRename(p) } label: { Label(L10n.t("common.rename"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { vm.beginDelete(p) } label: { Label(L10n.t("common.delete"), systemImage: "trash") }
        } else {
            Button { vm.removePlaylistFromLibrary(p) } label: {
                Label(L10n.t("shell.library.remove"), systemImage: "minus.circle")
            }
        }
        Divider()
        Button { vm.copyPlaylistLink(p) } label: { Label(L10n.t("shell.action.copyLink"), systemImage: "link") }
        if vm.hasCustomPlaylistOrder {
            Button { vm.resetPlaylistOrder() } label: {
                Label(L10n.t("shell.playlist.resetOrder"), systemImage: "arrow.up.arrow.down")
            }
        }
    }

    /// Sidebar reordering. Mirrors the own-queue drag: reorder live as the
    /// row is dragged over a neighbour, commit on drop.
    private struct PlaylistDropDelegate: DropDelegate {
        let targetId: String
        let vm: NativeShellViewModel
        @Binding var draggedId: String?

        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

        func dropEntered(info: DropInfo) {
            guard let dragged = draggedId, dragged != targetId else { return }
            Task { @MainActor in vm.movePlaylist(fromId: dragged, toId: targetId) }
        }

        func performDrop(info: DropInfo) -> Bool {
            draggedId = nil
            return true
        }
    }

    /// Which top item (if any) reflects the current view, so we can
    /// highlight it like Spotify/Apple Music.
    private func isTopActive(_ id: String) -> Bool {
        switch id {
        case "home":    return vm.mainSection == .home
        case "explore": return vm.mainSection == .explore
        case "radio":   return vm.mainSection == .radio
        case "history": return vm.mainSection == .history
        case "statistics": return vm.mainSection == .statistics
        case "search":  return vm.mainSection == .search
        default:        return false
        }
    }

    private func isPlaylistActive(_ p: NativeShellViewModel.PlaylistSummary) -> Bool {
        vm.mainSection == .playlist(p)
    }

    // Locale-aware: Turkish uppercases "i" to "İ", and the default would
    // render "Çalma listelerin" as "ÇALMA LISTELERIN".
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased(with: L10n.locale))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.primary.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }

    private func sidebarRow(icon: String, label: String, active: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundColor(active ? .primary : .primary.opacity(0.7))
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .primary : .primary.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? Color.primary.opacity(0.10) : .clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func playlistRow(_ p: NativeShellViewModel.PlaylistSummary, active: Bool = false, circular: Bool = false) -> some View {
        let playing = vm.isNowPlayingCollection(p)
        return HStack(spacing: 10) {
            thumbnail(for: p)
                .frame(width: 28, height: 28)
                .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 3)))
            Text(p.title)
                .font(.system(size: 12, weight: active || playing ? .semibold : .regular))
                .foregroundColor(playing ? prefs.theme.accentColor
                                         : (active ? .primary : .primary.opacity(0.85)))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(prefs.theme.accentColor)
                    .help(L10n.t("shell.sidebar.playingFromThis"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? Color.primary.opacity(0.10) : .clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnail(for p: NativeShellViewModel.PlaylistSummary) -> some View {
        if let urlString = p.thumbnailURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.primary.opacity(0.06)
                }
            }
        } else {
            Color.primary.opacity(0.06)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(.primary.opacity(0.4))
                )
        }
    }
}

// MARK: - Create playlist overlay

private struct CreatePlaylistOverlay: View {
    @ObservedObject var vm: NativeShellViewModel
    @State private var name: String = ""
    @State private var desc: String = ""
    @State private var privacy: NativeShellViewModel.PlaylistPrivacy = .privateListed
    @State private var cover: NSImage?
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { vm.cancelCreatePlaylist() }

            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("shell.playlist.new"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                HStack(alignment: .top, spacing: 16) {
                    coverWell
                    VStack(alignment: .leading, spacing: 10) {
                        field(L10n.t("shell.playlist.namePlaceholder"), text: $name)
                            .focused($nameFocused)
                        field(L10n.t("shell.playlist.descPlaceholder"), text: $desc)
                        privacyPicker
                    }
                }

                Text(L10n.t("shell.playlist.coverNote"))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button(L10n.t("common.cancel")) { vm.cancelCreatePlaylist() }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.createPlaylist(title: name, description: desc, privacy: privacy) }) {
                        Text(L10n.t("common.create"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(canCreate ? Color.accentColor : Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                }
            }
            .padding(20)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .environment(\.colorScheme, .dark) // dark dialog on any theme
        .onAppear { nameFocused = true }
    }

    private var coverWell: some View {
        Button(action: pickCover) {
            ZStack {
                if let cover {
                    Image(nsImage: cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.08)
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(.white.opacity(0.5))
                        Text(L10n.t("shell.playlist.pickCover"))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }

    private var privacyPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Picker("", selection: $privacy) {
                ForEach(NativeShellViewModel.PlaylistPrivacy.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.white)
        }
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            cover = img
        }
    }
}

// MARK: - Similar-playlist overlay (name + privacy, then animated progress)

private struct SimilarPlaylistOverlay: View {
    @ObservedObject var vm: NativeShellViewModel
    @State private var name: String = ""
    @State private var privacy: NativeShellViewModel.PlaylistPrivacy = .privateListed
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    switch vm.similarStage {
                    case .form: vm.cancelSimilarPlaylist()
                    case .done: vm.finishSimilarPlaylist()
                    default: break  // ignore taps mid-build
                    }
                }

            Group {
                switch vm.similarStage {
                case .form:            formCard
                case .done(let count): successCard(count: count)
                default:               progressCard
                }
            }
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            name = vm.similarDefaultTitle
            nameFocused = true
        }
    }

    // MARK: Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("shell.similar.title"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    if let seed = vm.similarSeed {
                        Text("\(seed.title) • \(ArtistName.primary(seed.artist))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                field(L10n.t("shell.playlist.namePlaceholder"), text: $name)
                    .focused($nameFocused)
                privacyPicker
            }

            Text(L10n.t("shell.similar.note"))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.t("common.cancel")) { vm.cancelSimilarPlaylist() }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                Button(action: { vm.confirmSimilarPlaylist(title: name, privacy: privacy) }) {
                    Text(L10n.t("common.create"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(canCreate ? Color.accentColor : Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
        }
        .padding(20)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Progress

    private var progressCard: some View {
        VStack(spacing: 18) {
            EqualizerBars(color: Color.accentColor)

            Text(stageTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .animation(.default, value: stageTitle)

            if case let .matching(done, total) = vm.similarStage, total > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                                .animation(.easeOut(duration: 0.3), value: done)
                        }
                    }
                    .frame(height: 5)
                    Text(L10n.t("shell.similar.matched", done, total))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(width: 240)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var stageTitle: String {
        switch vm.similarStage {
        case .form, .done: return ""
        case .fetching:    return L10n.t("shell.similar.stage.fetching")
        case .matching:    return L10n.t("shell.similar.stage.matching")
        case .creating:    return L10n.t("shell.similar.stage.creating")
        }
    }

    // MARK: Success

    private func successCard(count: Int) -> some View {
        VStack(spacing: 16) {
            SuccessTick(color: Color.accentColor)
            VStack(spacing: 4) {
                Text(L10n.t("shell.similar.done"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(L10n.plural("shell.similar.doneDetail", count))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            Button(action: { vm.finishSimilarPlaylist() }) {
                Text(L10n.t("common.ok"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26).padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)  // Enter confirms
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Shared field helpers (mirrors CreatePlaylistOverlay)

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private var privacyPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            Picker("", selection: $privacy) {
                ForEach(NativeShellViewModel.PlaylistPrivacy.allCases) { p in Text(p.label).tag(p) }
            }
            .labelsHidden().pickerStyle(.menu).tint(.white)
        }
    }
}

/// The checkmark springs in when the build finishes.
private struct SuccessTick: View {
    let color: Color
    @State private var shown = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 48))
            .foregroundColor(color)
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            }
    }
}

/// A little equalizer that dances while the playlist is being built — nicer
/// than a spinner and on-theme for a music app.
private struct EqualizerBars: View {
    let color: Color
    @State private var animating = false
    private let heights: [CGFloat] = [14, 30, 20, 36, 24]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 6, height: animating ? heights[i] : 8)
                    .animation(.easeInOut(duration: 0.45)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.11), value: animating)
            }
        }
        .frame(height: 40)
        .onAppear { animating = true }
    }
}

// MARK: - Rename / delete playlist overlays

private struct RenamePlaylistOverlay: View {
    @ObservedObject var vm: NativeShellViewModel
    let playlist: NativeShellViewModel.PlaylistSummary
    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var canSave: Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t != playlist.title
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { vm.cancelRename() }
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("common.rename"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                TextField(L10n.t("shell.playlist.namePlaceholder"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))
                    .onSubmit { if canSave { vm.renamePlaylist(playlist, to: name) } }
                HStack(spacing: 10) {
                    Spacer()
                    Button(L10n.t("common.cancel")) { vm.cancelRename() }
                        .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.renamePlaylist(playlist, to: name) }) {
                        Text(L10n.t("common.save"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(canSave ? Color.accentColor : Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain).disabled(!canSave)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.10, green: 0.10, blue: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { name = playlist.title; focused = true }
    }
}

private struct DeleteConfirmOverlay: View {
    @ObservedObject var vm: NativeShellViewModel
    let playlist: NativeShellViewModel.PlaylistSummary

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { vm.cancelDelete() }
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("shell.playlist.deleteTitle"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(L10n.t("shell.playlist.deleteBody", playlist.title))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    Button(L10n.t("common.cancel")) { vm.cancelDelete() }
                        .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.confirmDeletePlaylist() }) {
                        Text(L10n.t("common.delete"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.10, green: 0.10, blue: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Main content

private struct MainContent: View {
    let bg: Color
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            bg.ignoresSafeArea()
            switch vm.mainSection {
            case .home:
                HomeView(vm: vm)
            case .explore:
                ExploreView(vm: vm)
            case .radio:
                RadioView(vm: vm)
            case .history:
                HistoryView(vm: vm)
            case .statistics:
                StatisticsView(vm: vm)
            case .search:
                SearchView(vm: vm)
            case .playlist(let p):
                PlaylistDetailView(playlist: p, vm: vm)
            case .category:
                CategoryView(vm: vm)
            case .artist:
                ArtistView(vm: vm)
            case .empty:
                emptyState
            }
            // Floating back/forward — always visible in the top-left of
            // the main area. Last-resort affordance when mouse buttons
            // and keyboard shortcuts fail (driver swallowing, etc.).
            NavButtons(vm: vm)
                .padding(.leading, 12)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.primary.opacity(0.35))
            Text(L10n.t("shell.empty.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text(L10n.t("shell.empty.subtitle"))
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.45))
        }
    }
}

// MARK: - Floating nav buttons

private struct NavButtons: View {
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        HStack(spacing: 6) {
            button(systemName: "chevron.left",
                   enabled: vm.canGoBack,
                   help: L10n.t("shell.nav.back")) { vm.goBack() }
            button(systemName: "chevron.right",
                   enabled: vm.canGoForward,
                   help: L10n.t("shell.nav.forward")) { vm.goForward() }
        }
    }

    private func button(systemName: String,
                        enabled: Bool,
                        help: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.45))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(enabled ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Artist view

private struct ArtistView: View {
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                if vm.artistLoading && vm.artistDetail == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let msg = vm.artistError, vm.artistDetail == nil {
                    Text(msg).foregroundColor(.primary.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let a = vm.artistDetail {
                    header(a)
                    if !a.topSongs.isEmpty { topSongs(a) }
                    if !a.albums.isEmpty {
                        CarouselSection(
                            title: L10n.t("shell.artist.albums"),
                            subtitle: nil,
                            items: a.albums,
                            pageSize: 3,
                            estimatedItemWidth: 162
                        ) { card in
                            Button(action: { vm.openHomeCard(card) }) {
                                HomeCardView(card: card)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { homeCardContextMenu(card, vm) }
                        }
                    }
                    if !a.singles.isEmpty {
                        CarouselSection(
                            title: L10n.t("shell.artist.singles"),
                            subtitle: nil,
                            items: a.singles,
                            pageSize: 3,
                            estimatedItemWidth: 162
                        ) { card in
                            Button(action: { vm.openHomeCard(card) }) {
                                HomeCardView(card: card)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { homeCardContextMenu(card, vm) }
                        }
                    }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private func header(_ a: NativeShellViewModel.ArtistDetail) -> some View {
        HStack(spacing: 18) {
            Group {
                if let s = a.thumbnailURL, let url = URL(string: s) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.primary.opacity(0.06)
                        }
                    }
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("shell.artist.kindLabel"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(a.name)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let s = a.subscriberText {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.55))
                }
            }
            Spacer()
        }
    }

    private func topSongs(_ a: NativeShellViewModel.ArtistDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("shell.artist.topSongs"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if let bid = a.allSongsBrowseId {
                    Button(L10n.t("shell.artist.allSongs")) {
                        vm.openPlaylist(.init(id: bid, title: a.name, thumbnailURL: a.thumbnailURL))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(a.topSongs.prefix(10).enumerated()), id: \.element.id) { idx, track in
                    Button(action: {
                        // Convert HomeCard-style click → play this song
                        let card = NativeShellViewModel.HomeCard(
                            id: track.id, kind: .song,
                            title: track.title, subtitle: track.artist,
                            thumbnailURL: track.thumbnailURL,
                            playlistId: nil)
                        vm.openHomeCard(card)
                    }) {
                        TrackRow(index: idx + 1, track: track,
                                 isPlaying: isCurrentTrack(track),
                                 zebra: idx.isMultiple(of: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isCurrentTrack(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }
}

// MARK: - History view

private struct HistoryView: View {
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if vm.historyLoading && vm.historySections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let msg = vm.historyError, vm.historySections.isEmpty {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(vm.historySections) { ChartSectionView(section: $0, vm: vm) }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("shell.history.kindLabel"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(L10n.t("shell.history.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.t("shell.history.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            Spacer()
            Button(action: { vm.reloadHistory() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L10n.t("shell.history.reload"))
        }
    }
}

// MARK: - Category (mood/genre) view

private struct CategoryView: View {
    @ObservedObject var vm: NativeShellViewModel
    @ObservedObject private var prefs = Preferences.shared

    private var layout: CategoryLayout { prefs.categoryLayout }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: layout.coverSize), spacing: layout == .largeGrid ? 16 : 12)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if vm.categoryLoading && vm.categoryPlaylists.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let msg = vm.categoryError, vm.categoryPlaylists.isEmpty {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if layout == .list {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.categoryPlaylists.enumerated()), id: \.element.id) { idx, p in
                            entry(p) {
                                CategoryPlaylistRow(playlist: p, saved: vm.isPlaylistSaved(p),
                                                    zebra: idx.isMultiple(of: 2))
                            }
                        }
                    }
                    Spacer(minLength: 40)
                } else {
                    LazyVGrid(columns: columns, spacing: layout == .largeGrid ? 18 : 14) {
                        ForEach(vm.categoryPlaylists) { p in
                            entry(p) {
                                CategoryPlaylistCard(playlist: p, saved: vm.isPlaylistSaved(p),
                                                     size: layout.coverSize)
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    /// One playlist, whatever its shape: tap opens it, right-click saves it.
    private func entry<Content: View>(_ p: NativeShellViewModel.PlaylistSummary,
                                      @ViewBuilder content: () -> Content) -> some View {
        Button(action: { vm.openPlaylist(p) }) { content() }
            .buttonStyle(.plain)
            .contextMenu {
                Button { vm.openPlaylist(p) } label: {
                    Label(L10n.t("common.open"), systemImage: "arrow.right.circle")
                }
                Button { vm.openPlaylist(p, autoplay: true) } label: {
                    Label(L10n.t("transport.play"), systemImage: "play.fill")
                }
                Divider()
                if vm.isPlaylistSaved(p) {
                    Button { vm.removePlaylistFromLibrary(p) } label: {
                        Label(L10n.t("shell.library.remove"), systemImage: "minus.circle")
                    }
                } else {
                    Button { vm.savePlaylistToLibrary(p) } label: {
                        Label(L10n.t("shell.library.save"), systemImage: "plus.circle")
                    }
                }
                Divider()
                Button { vm.copyPlaylistLink(p) } label: {
                    Label(L10n.t("shell.action.copyLink"), systemImage: "link")
                }
            }
    }

    private var layoutPicker: some View {
        HStack(spacing: 2) {
            ForEach(CategoryLayout.allCases) { mode in
                Button(action: { prefs.categoryLayout = mode }) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(mode == layout ? .primary : .primary.opacity(0.5))
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(mode == layout ? Color.primary.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("shell.category.kindLabel"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(vm.categoryTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                if !vm.categoryPlaylists.isEmpty {
                    Text(L10n.plural("shell.playlistCount", vm.categoryPlaylists.count))
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.5))
                }
            }
            Spacer()
            layoutPicker
        }
    }
}

private struct CategoryPlaylistCard: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    /// Already in the user's library — badged so a category grid tells you
    /// what you've saved without opening every card.
    let saved: Bool
    let size: CGFloat
    @State private var hovered: Bool = false

    private var compact: Bool { size < 140 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            PlaylistCover(url: playlist.thumbnailURL)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let n = playlist.trackCount { CountBadge(count: n, compact: compact) }
                }
                .overlay(alignment: .topTrailing) {
                    if saved { SavedBadge(compact: compact) }
                }
                .scaleEffect(hovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(hovered ? 0.5 : 0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: hovered)
            Text(playlist.title)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: size, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

/// Row form of the same card — thumbnail, title, YT's subtitle, count.
private struct CategoryPlaylistRow: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    let saved: Bool
    let zebra: Bool
    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            PlaylistCover(url: playlist.thumbnailURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let sub = playlist.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if saved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .help(L10n.t("shell.library.savedBadge"))
            }
            if let n = playlist.trackCount {
                Text(L10n.plural("shell.songCount", n))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.5))
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovered ? Color.primary.opacity(0.08)
                              : (zebra ? Color.primary.opacity(0.03) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct SavedBadge: View {
    let compact: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: compact ? 8 : 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: compact ? 17 : 22, height: compact ? 17 : 22)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .padding(compact ? 5 : 8)
            .help(L10n.t("shell.library.savedBadge"))
    }
}

/// Track count sits ON the artwork, so it needs its own scrim — YT covers
/// range from near-white to near-black.
private struct CountBadge: View {
    let count: Int
    let compact: Bool

    var body: some View {
        Text(compact ? "\(count)" : L10n.plural("shell.songCount", count))
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .padding(compact ? 5 : 7)
            .help(L10n.plural("shell.songCount", count))
    }
}

private struct PlaylistCover: View {
    let url: String?

    @ViewBuilder
    var body: some View {
        if let s = url, let u = URL(string: s) {
            CachedAsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color.primary.opacity(0.06)
                }
            }
        } else {
            Color.primary.opacity(0.06)
        }
    }
}

// MARK: - Home view

private struct HomeView: View {
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                header
                if vm.homeLoading && vm.homeShelves.isEmpty && vm.genreSections.isEmpty {
                    loadingState
                } else if let msg = vm.homeError, vm.homeShelves.isEmpty {
                    errorState(msg)
                } else {
                    // Ours first: these are built from local history and are
                    // the thing YT's own home can't offer.
                    if !vm.dailyStations.isEmpty { dailyDiscoveryRow }
                    ForEach(vm.personalShelves) { shelf in
                        PersonalShelfRow(shelf: shelf, vm: vm)
                    }
                    ForEach(vm.homeShelves) { shelf in
                        ShelfRow(shelf: shelf, vm: vm)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(L10n.t("shell.home.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.t("shell.home.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            Spacer()
            Button(action: { vm.reloadHome() }) {
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

    private var dailyDiscoveryRow: some View {
        CarouselSection(
            title: L10n.t("shell.home.dailyDiscovery.title"),
            subtitle: nil,
            icon: "sparkles",
            caption: L10n.t("shell.home.dailyDiscovery.subtitle"),
            items: vm.dailyStations,
            pageSize: 3,
            estimatedItemWidth: 162
        ) { station in
            Button(action: { vm.startRadio(station) }) {
                RadioStationTile(station: station, onPlay: { vm.startRadio(station) })
            }
            .buttonStyle(.plain)
            .contextMenu { radioStationContextMenu(station, vm) }
        }
    }

    /// Greeting changes through the day so home doesn't feel static
    /// across long sessions. No name yet — we don't fetch user identity.
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return L10n.t("shell.greeting.morning")
        case 12..<18: return L10n.t("shell.greeting.afternoon")
        case 18..<23: return L10n.t("shell.greeting.evening")
        default:      return L10n.t("shell.greeting.night")
        }
    }

    private var loadingState: some View {
        HomeExploreSkeleton(rows: 3)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.primary.opacity(0.4))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.6))
            Button(L10n.t("common.retry")) { vm.reloadHome() }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.primary.opacity(0.1))
                )
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

// MARK: - Explore

private struct ExploreView: View {
    @ObservedObject var vm: NativeShellViewModel

    private var isEmpty: Bool {
        vm.exploreNewReleases.isEmpty && vm.exploreCharts.isEmpty && vm.genreSections.isEmpty
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                header
                if vm.exploreLoading && isEmpty {
                    loadingState
                } else if let msg = vm.exploreError, isEmpty {
                    errorState(msg)
                } else {
                    if !vm.exploreNewReleases.isEmpty {
                        sectionLabel(L10n.t("shell.explore.newReleases"))
                        ForEach(vm.exploreNewReleases) { ShelfRow(shelf: $0, vm: vm) }
                    }
                    if !vm.exploreCharts.isEmpty {
                        sectionLabel(L10n.t("shell.explore.charts"))
                        ForEach(vm.exploreCharts) { ChartSectionView(section: $0, vm: vm) }
                    }
                    if !vm.genreSections.isEmpty {
                        sectionLabel(L10n.t("shell.explore.genresMoods"))
                        ForEach(vm.genreSections) { GenreCarousel(section: $0, vm: vm) }
                    }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("shell.explore.kindLabel"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(L10n.t("shell.explore.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.t("shell.explore.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            Spacer()
            Button(action: { vm.reloadExplore() }) {
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

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.primary)
            .padding(.bottom, -12)
    }

    private var loadingState: some View {
        HomeExploreSkeleton(rows: 3)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.primary.opacity(0.4))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.6))
            Button(L10n.t("common.retry")) { vm.reloadExplore() }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

/// One chart ("Top songs", "Trending") as a numbered vertical list. Rank
/// is the row position; rows reuse TrackRow and play on click.
private struct ChartSectionView: View {
    let section: NativeShellViewModel.ChartSection
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            VStack(spacing: 0) {
                // Keyed by position, not videoId — history legitimately
                // repeats the same track within a day.
                ForEach(Array(section.tracks.enumerated()), id: \.offset) { idx, track in
                    Button(action: { vm.playTrack(track) }) {
                        TrackRow(index: idx + 1,
                                 track: track,
                                 isPlaying: isCurrent(track),
                                 zebra: idx.isMultiple(of: 2))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { vm.playTrack(track) } label: { Label(L10n.t("transport.play"), systemImage: "play.fill") }
                        Button { vm.addToQueue(track: track, playNext: true) } label: {
                            Label(L10n.t("shell.queue.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button { vm.addToQueue(track: track) } label: { Label(L10n.t("shell.queue.add"), systemImage: "text.append") }
                        Button { vm.startRadio(track) } label: {
                            Label(L10n.t("shell.action.startRadio"), systemImage: "dot.radiowaves.left.and.right")
                        }
                        Button { vm.startSimilarPlaylist(seed: track) } label: {
                            Label(L10n.t("shell.action.similarPlaylist"), systemImage: "square.stack.3d.up")
                        }
                                                Divider()
                        Menu {
                            Button { vm.beginCreatePlaylist(addingVideoId: track.id) } label: {
                                Label(L10n.t("shell.playlist.createNew"), systemImage: "plus")
                            }
                            if !vm.playlists.isEmpty { Divider() }
                            ForEach(vm.playlists) { p in
                                Button(p.title) {
                                    vm.addToPlaylist(videoId: track.id, playlistId: p.id,
                                                     trackTitle: track.title, playlistTitle: p.title)
                                }
                            }
                        } label: { Label(L10n.t("shell.playlist.addTo"), systemImage: "plus") }
                        Button { vm.likeTrack(videoId: track.id, title: track.title) } label: {
                            Label(L10n.t("shell.action.saveToLiked"), systemImage: "heart")
                        }
                        Button { vm.openInBrowser(videoId: track.id) } label: { Label(L10n.t("shell.action.openInBrowser"), systemImage: "safari") }
                    }
                }
            }
        }
    }

    private func isCurrent(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }
}

private struct ShelfRow: View {
    let shelf: NativeShellViewModel.HomeShelf
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        CarouselSection(
            title: shelf.title,
            subtitle: shelf.subtitle,
            items: shelf.items,
            pageSize: 3,
            estimatedItemWidth: 162   // 150 card + 12 spacing
        ) { card in
            Button(action: { vm.openHomeCard(card) }) {
                HomeCardView(card: card,
                             onPlay: card.kind == .artist ? nil : { vm.playHomeCard(card) })
            }
            .buttonStyle(.plain)
            .contextMenu { homeCardContextMenu(card, vm) }
        }
    }
}

/// A shelf built from the local play history. Unlike `ShelfRow` these carry
/// real tracks, so the row plays as a list: the header pill starts it from the
/// top and a tile starts it from that track onwards.
private struct PersonalShelfRow: View {
    let shelf: NativeShellViewModel.PersonalShelf
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        CarouselSection(
            title: shelf.title,
            subtitle: nil,
            icon: shelf.icon,
            caption: shelf.subtitle,
            onPlayAll: { vm.playPersonalShelf(shelf) },
            items: shelf.tracks,
            pageSize: 3,
            estimatedItemWidth: 162
        ) { stat in
            let card = Self.card(for: stat)
            Button(action: { play(from: stat) }) {
                HomeCardView(card: card, onPlay: { play(from: stat) })
            }
            .buttonStyle(.plain)
            .contextMenu { homeCardContextMenu(card, vm) }
        }
    }

    private func play(from stat: TrackStat) {
        vm.playLocalTracks(Array(shelf.tracks.drop(while: { $0.id != stat.id })))
    }

    private static func card(for stat: TrackStat) -> NativeShellViewModel.HomeCard {
        NativeShellViewModel.HomeCard(id: stat.videoId,
                                      kind: .song,
                                      title: stat.title,
                                      subtitle: stat.artist,
                                      thumbnailURL: stat.artworkURL,
                                      playlistId: nil)
    }
}

/// Shared right-click menu for a HomeCard (used by Home/Explore shelves and
/// the artist page's album/single carousels). Actions depend on card kind.
@MainActor @ViewBuilder
func homeCardContextMenu(_ card: NativeShellViewModel.HomeCard,
                         _ vm: NativeShellViewModel) -> some View {
    switch card.kind {
    case .song:
        let t = NativeShellViewModel.TrackSummary(
            id: card.id, title: card.title, artist: card.subtitle,
            duration: nil, thumbnailURL: card.thumbnailURL)
        Button { vm.openHomeCard(card) } label: { Label(L10n.t("transport.play"), systemImage: "play.fill") }
        Button { vm.addToQueue(track: t, playNext: true) } label: {
            Label(L10n.t("shell.queue.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { vm.addToQueue(track: t) } label: { Label(L10n.t("shell.queue.add"), systemImage: "text.append") }
        Divider()
        Menu {
            Button { vm.beginCreatePlaylist(addingVideoId: card.id) } label: {
                Label(L10n.t("shell.playlist.createNew"), systemImage: "plus")
            }
            if !vm.playlists.isEmpty { Divider() }
            ForEach(vm.playlists) { p in
                Button(p.title) {
                    vm.addToPlaylist(videoId: card.id, playlistId: p.id,
                                     trackTitle: card.title, playlistTitle: p.title)
                }
            }
        } label: { Label(L10n.t("shell.playlist.addTo"), systemImage: "plus") }
        Button { vm.likeTrack(videoId: card.id, title: card.title) } label: {
            Label(L10n.t("shell.action.saveToLiked"), systemImage: "heart")
        }
        Divider()
        Button { vm.copyLink(videoId: card.id) } label: { Label(L10n.t("shell.action.copyLink"), systemImage: "link") }
        Button { vm.openInBrowser(videoId: card.id) } label: { Label(L10n.t("shell.action.openInBrowser"), systemImage: "safari") }
    case .playlist, .album:
        let p = NativeShellViewModel.PlaylistSummary(
            id: card.id, title: card.title, thumbnailURL: card.thumbnailURL)
        Button { vm.playHomeCard(card) } label: { Label(L10n.t("transport.play"), systemImage: "play.fill") }
        Button { vm.addCollectionToQueue(id: card.id, title: card.title) } label: {
            Label(L10n.t("shell.queue.add"), systemImage: "text.append")
        }
        Button { vm.openHomeCard(card) } label: { Label(L10n.t("common.open"), systemImage: "arrow.right.circle") }
        Button { vm.savePlaylistToLibrary(p) } label: {
            Label(L10n.t("shell.library.save"), systemImage: "plus.circle")
        }
        Button { vm.copyPlaylistLink(p) } label: { Label(L10n.t("shell.action.copyLink"), systemImage: "link") }
    case .artist:
        Button { vm.openArtist(browseId: card.id, name: card.title) } label: {
            Label(L10n.t("shell.action.goToArtist"), systemImage: "music.mic")
        }
    }
}

/// One reusable carousel row used by every horizontal section on Home.
/// Header (title + optional strapline) on the left, paired chevron pills
/// on the right of the same row. Chevrons stay visible (no hover) and
/// fade their fill when there's no further scroll in that direction.
struct CarouselSection<Item: Identifiable, Content: View>: View where Item.ID: Hashable {
    let title: String
    let subtitle: String?
    /// SF Symbol before the title, marking a row as one of ours rather than
    /// one of YT's.
    var icon: String? = nil
    /// Sentence-length strapline under the title. `subtitle` is an uppercase
    /// eyebrow above the title and turns anything longer than a label into
    /// shouting.
    var caption: String? = nil
    /// Set when the whole row is playable as a list — renders a play pill in
    /// the header.
    var onPlayAll: (() -> Void)? = nil
    let items: [Item]
    /// How many items to step per chevron click.
    let pageSize: Int
    /// Approximate per-item width (incl. spacing). Used to decide whether
    /// the row needs scrolling at all — when the content fits the
    /// container the chevrons hide entirely so we don't decorate
    /// non-interactive rows.
    let estimatedItemWidth: CGFloat
    @ViewBuilder let content: (Item) -> Content

    /// Index of the leading visible item — drives the chevron's enabled
    /// state. Updated by the chevrons; trackpad scroll doesn't (and
    /// doesn't need to — we just want sane enable/disable).
    @State private var currentIndex: Int = 0
    /// Measured scroll-row width. 0 until the first onAppear fires.
    @State private var rowWidth: CGFloat = 0

    private var contentWidth: CGFloat {
        CGFloat(items.count) * estimatedItemWidth
    }
    /// True when the row actually overflows its container. Until the
    /// first GeometryReader update lands (rowWidth still 0) we fall
    /// back to a generous 1400px assumption — any normal window is
    /// narrower than that, so a row whose content exceeds 1400px will
    /// definitely overflow.
    private var needsScroll: Bool {
        if rowWidth > 0 {
            return contentWidth > rowWidth + 1
        }
        return contentWidth > 1400
    }
    private var canLeft: Bool  { needsScroll && currentIndex > 0 }
    private var canRight: Bool { needsScroll && currentIndex < max(0, items.count - 1) }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header(proxy: proxy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            content(item).id(item.id)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .overlay(
                    // Zero-sized measurement layer — reports the ScrollView's
                    // own width, which is what content has to fit inside.
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { rowWidth = geo.size.width }
                            .onChange(of: geo.size.width) { newValue in
                                rowWidth = newValue
                            }
                    }
                )
            }
        }
    }

    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = subtitle, !s.isEmpty {
                    Text(s.uppercased(with: L10n.locale))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.primary.opacity(0.5))
                }
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.55))
                    }
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                if let c = caption, !c.isEmpty {
                    Text(c)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.5))
                }
            }
            Spacer()
            if let onPlayAll {
                playAllPill(onPlayAll)
            }
            if needsScroll {
                navChevron(.leftward, proxy: proxy)
                navChevron(.rightward, proxy: proxy)
            }
        }
    }

    private func playAllPill(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                Text(L10n.t("transport.play")).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.10)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private enum Direction { case leftward, rightward }

    private func navChevron(_ dir: Direction, proxy: ScrollViewProxy) -> some View {
        let enabled = dir == .leftward ? canLeft : canRight
        return Button(action: { step(dir, proxy: proxy) }) {
            Image(systemName: dir == .leftward ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(enabled ? 0.10 : 0.04))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(enabled ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func step(_ dir: Direction, proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let delta = (dir == .leftward ? -1 : 1) * pageSize
        let next = max(0, min(items.count - 1, currentIndex + delta))
        guard next != currentIndex else { return }
        currentIndex = next
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(items[next].id, anchor: .leading)
        }
    }
}

/// One section of the moods/genres landing — its own row with a section
/// title and a horizontally scrolling carousel of coloured chips. We do
/// one per YT-side gridRenderer so the user gets the same grouping the
/// web UI has (Moods & moments / Genres / Decades / etc.).
struct GenreCarousel: View {
    let section: NativeShellViewModel.GenreSection
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        CarouselSection(
            title: section.title,
            subtitle: nil,
            items: section.chips,
            pageSize: 4,
            estimatedItemWidth: 212   // 200 chip + 12 spacing
        ) { g in
            Button(action: { vm.openGenre(g) }) {
                GenreChipView(genre: g)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Coloured tile with the genre title. Prefers YT's own brand color (when
/// present in the response), falling back to a deterministic hue from the
/// title so the palette is stable across sessions.
private struct GenreChipView: View {
    let genre: NativeShellViewModel.GenreChip
    @State private var hovered: Bool = false

    private var bg: Color {
        if let c = genre.color {
            // YT ships RGB packed as 0xFFRRGGBB; mask the alpha out.
            let r = Double((c >> 16) & 0xFF) / 255.0
            let g = Double((c >> 8) & 0xFF) / 255.0
            let b = Double(c & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        let hash = abs(genre.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.45)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bg)
                .frame(width: 200, height: 96)
            // Subtle darken-from-bottom-right gradient so text stays
            // readable on lighter brand colours.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(colors: [.clear, .black.opacity(0.3)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .frame(width: 200, height: 96)
            Text(genre.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 180, alignment: .leading)
            // Tilted card-back decoration in the bottom-right corner,
            // same visual idiom YT Music uses on these tiles.
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(25))
                    .offset(x: geo.size.width - 46, y: geo.size.height - 34)
            }
            .frame(width: 200, height: 96)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(hovered ? 0.3 : 0), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(hovered ? 0.4 : 0), radius: 8, y: 4)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

struct HomeCardView: View {
    let card: NativeShellViewModel.HomeCard
    /// Play action for the hover overlay. nil → no play button (artists).
    var onPlay: (() -> Void)? = nil
    @State private var hovered: Bool = false
    @ObservedObject private var prefs = Preferences.shared

    private var coverShape: AnyShape {
        card.kind == .artist
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(card.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 150, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = card.thumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.primary.opacity(0.06)
                }
            }
        } else {
            Color.primary.opacity(0.06)
        }
    }
}

private enum TrackSortField { case index, title, artist, album, duration }

private struct PlaylistDetailView: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    @State private var searchText: String = ""
    @State private var sortField: TrackSortField = .index
    @State private var sortAscending: Bool = true
    @State private var selectedIDs: Set<String> = []
    @State private var anchorIndex: Int?
    @State private var draggedSetVideoId: String?
    @ObservedObject private var prefs = Preferences.shared

    /// Reorder is only meaningful on your own playlist in natural order with
    /// no active search filter (otherwise drag positions don't map to the
    /// real playlist order).
    private var canReorder: Bool {
        vm.isEditablePlaylist(playlist) && sortField == .index && searchText.isEmpty
    }

    private var accentGreen: Color { prefs.theme.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.primary.opacity(0.08))
            if !vm.tracks.isEmpty {
                if selectedIDs.isEmpty { toolbar } else { selectionBar }
                columnHeader
                Divider().background(Color.primary.opacity(0.06))
            }
            tracksList
        }
        .background(selectAllShortcut)
        .onChange(of: playlist.id) { _ in clearSelection() }
        .onChange(of: searchText) { _ in clearSelection() }
    }

    // MARK: Multi-select

    /// Selected tracks in display order (so they're added in the order shown).
    private func selectedVideoIds() -> [String] {
        displayedTracks.filter { selectedIDs.contains($0.id) }.map { $0.id }
    }
    private func clearSelection() { selectedIDs.removeAll(); anchorIndex = nil }
    private func selectAll() { selectedIDs = Set(displayedTracks.map { $0.id }); anchorIndex = nil }

    /// Row click: plain = play (+clear), ⌘ = toggle, ⇧ = range from anchor.
    private func handleRowTap(_ track: NativeShellViewModel.TrackSummary, _ index: Int) {
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) {
            if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) }
            else { selectedIDs.insert(track.id) }
            anchorIndex = index
        } else if mods.contains(.shift) {
            let a = anchorIndex ?? index
            let lo = min(a, index), hi = max(a, index)
            if displayedTracks.indices.contains(lo), displayedTracks.indices.contains(hi) {
                selectedIDs.formUnion(displayedTracks[lo...hi].map { $0.id })
            }
        } else {
            clearSelection()
            anchorIndex = index
            vm.playTrack(track)
        }
    }

    /// Invisible button so ⌘A selects all while this view is on screen.
    private var selectAllShortcut: some View {
        Button("") { selectAll() }
            .keyboardShortcut("a", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text(L10n.t("shell.selectedCount", selectedIDs.count))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(L10n.t("shell.action.selectAll")) { selectAll() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.7))
            Menu {
                Button { vm.beginCreatePlaylist(addingVideoIds: selectedVideoIds()); clearSelection() } label: {
                    Label(L10n.t("shell.playlist.createNew"), systemImage: "plus")
                }
                if !vm.playlists.isEmpty { Divider() }
                ForEach(vm.playlists) { p in
                    Button(p.title) {
                        vm.addTracksToPlaylist(videoIds: selectedVideoIds(), playlistId: p.id, playlistTitle: p.title)
                        clearSelection()
                    }
                }
            } label: {
                Label(L10n.t("shell.playlist.addTo"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if vm.isEditablePlaylist(playlist) {
                Button(L10n.t("shell.playlist.removeFrom")) {
                    vm.removeFromPlaylist(tracks: displayedTracks.filter { selectedIDs.contains($0.id) }, from: playlist)
                    clearSelection()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.red.opacity(0.9))
            }
            Button(L10n.t("shell.action.clear")) { clearSelection() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// Filtered + sorted view of the tracks. The View Model's `tracks`
    /// stays untouched (original order) — this is display-only state.
    private var displayedTracks: [NativeShellViewModel.TrackSummary] {
        var arr = vm.tracks
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            arr = arr.filter {
                $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || ($0.album?.lowercased().contains(q) ?? false)
            }
        }
        switch sortField {
        case .index: break // natural order
        case .title:    arr.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:   arr.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:    arr.sort { ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "") == .orderedAscending }
        case .duration: arr.sort { (parseDurationSeconds($0.duration) ?? 0) < (parseDurationSeconds($1.duration) ?? 0) }
        }
        if !sortAscending { arr.reverse() }
        return arr
    }

    private func toggleSort(_ f: TrackSortField) {
        if sortField == f { sortAscending.toggle() }
        else { sortField = f; sortAscending = true }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.45))
                TextField(L10n.t("shell.playlist.searchPlaceholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .frame(maxWidth: 260)
            Spacer()
            if !searchText.isEmpty {
                Text(L10n.plural("shell.resultCount", displayedTracks.count))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var showAlbumColumn: Bool { !isAlbum }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            sortHeader(field: .index) { Text("#") }
                .frame(width: 28, alignment: .trailing)
            sortHeader(field: .title) { Text(L10n.t("shell.column.title")) }
                .frame(maxWidth: .infinity, alignment: .leading)
            if showAlbumColumn {
                sortHeader(field: .album) { Text(L10n.t("shell.column.album")) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            sortHeader(field: .duration) {
                Image(systemName: "clock").font(.system(size: 12))
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func sortHeader<Label: View>(field: TrackSortField, @ViewBuilder label: () -> Label) -> some View {
        let active = sortField == field
        Button(action: { toggleSort(field) }) {
            HStack(spacing: 4) {
                label()
                if active {
                    Image(systemName: sortAscending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(active ? accentGreen : .primary.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Header label for the detail view — derived from the browseId
    /// prefix so albums get "ALBUM", everything else stays "PLAYLIST".
    private var kindLabel: String {
        L10n.t(isAlbum ? "shell.detail.album" : "shell.detail.playlist")
    }

    /// MPRE… / OLAK… are YT's album id namespaces; everything else
    /// (VLPL…, VLRDA…) is a playlist.
    private var isAlbum: Bool {
        playlist.id.hasPrefix("MPRE") || playlist.id.hasPrefix("OLAK")
    }

    private var header: some View {
        HStack(spacing: 16) {
            cover
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.5))
                Text(playlist.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if !vm.tracks.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.6))
                }
            }
            Spacer()
            if !vm.tracks.isEmpty {
                playButton
                shuffleButton
                queueAllButton
            }
            if isAlbum { albumSaveButton } else { saveButton }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    /// This collection is the one feeding the player AND audio is running.
    private var isThisPlaying: Bool {
        vm.isNowPlayingCollection(playlist) && media.nowPlaying.isPlaying
    }

    private var playButton: some View {
        Button(action: {
            // Already this playlist → toggle; otherwise (re)start it.
            if vm.isNowPlayingCollection(playlist) {
                media.run("playpause")
            } else {
                vm.playPlaylist(displayedTracks)
            }
        }) {
            Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(prefs.theme.isDark ? .black : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accentGreen))
        }
        .buttonStyle(.plain)
        .help(L10n.t(isThisPlaying ? "transport.pause" : "transport.play"))
    }

    private var shuffleButton: some View {
        Button(action: { vm.shufflePlay(displayedTracks) }) {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.action.shuffle"))
    }

    private var queueAllButton: some View {
        Button(action: { vm.addTracksToQueue(displayedTracks) }) {
            Image(systemName: "text.append")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.queue.addAll"))
    }

    private var albumSaveButton: some View {
        Button(action: { vm.toggleAlbumSaved() }) {
            HStack(spacing: 6) {
                Image(systemName: vm.isAlbumSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 13))
                Text(L10n.t(vm.isAlbumSaved ? "shell.library.saved" : "common.save"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(vm.isAlbumSaved ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(vm.isAlbumSaved ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.t(vm.isAlbumSaved ? "shell.library.remove" : "shell.library.saveAlbum"))
    }

    /// "98 tracks · 5h 32min" — duration is summed from track row strings.
    private var metaLine: String {
        let trackPart = L10n.plural("shell.trackCount", vm.tracks.count)
        guard let dur = formattedTotalDuration else { return trackPart }
        return "\(trackPart) · \(dur)"
    }

    private var formattedTotalDuration: String? {
        let total = vm.tracks.reduce(0) { acc, t in
            acc + (parseDurationSeconds(t.duration) ?? 0)
        }
        guard total > 0 else { return nil }
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? L10n.t("shell.duration.hoursMinutes", h, m)
                     : L10n.t("shell.duration.minutes", m)
    }

    private func parseDurationSeconds(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        let parts = s.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private var saveButton: some View {
        let saved = vm.isPlaylistSaved(playlist)
        return Button(action: {
            if saved {
                vm.removePlaylistFromLibrary(playlist)
            } else {
                vm.savePlaylistToLibrary(playlist)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 13))
                Text(L10n.t(saved ? "shell.library.saved" : "common.save"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(saved ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(saved ? Color.clear : Color.primary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.t(saved ? "shell.library.remove" : "shell.library.save"))
    }

    @ViewBuilder
    private var cover: some View {
        if let s = playlist.thumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.primary.opacity(0.06)
                }
            }
        } else {
            Color.primary.opacity(0.06)
        }
    }

    @ViewBuilder
    private var tracksList: some View {
        if vm.loadingTracks && vm.tracks.isEmpty {
            VStack {
                ProgressView()
                Text(L10n.t("shell.tracks.loading"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.tracksError, vm.tracks.isEmpty {
            Text(msg)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedTracks.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.primary.opacity(0.3))
                Text(L10n.t("shell.search.noResultsFor", searchText))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { idx, track in
                        let row = Button(action: { handleRowTap(track, idx) }) {
                            TrackRow(index: idx + 1,
                                     track: track,
                                     isPlaying: isCurrentTrack(track),
                                     zebra: idx.isMultiple(of: 2),
                                     showAlbum: showAlbumColumn,
                                     selected: selectedIDs.contains(track.id),
                                     fallbackThumbnailURL: playlist.thumbnailURL,
                                     showClipIcon: isCurrentTrack(track) && media.nowPlaying.hasVideo,
                                     onClip: { vm.enterClip() })
                                // Only dim the row actually being dragged. Guard
                                // the nil case: a freshly-built list's rows have
                                // no setVideoId yet, and nil == nil would dim all.
                                .opacity(draggedSetVideoId != nil && draggedSetVideoId == track.setVideoId ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { trackContextMenu(for: track) }

                        if canReorder, let sv = track.setVideoId {
                            row
                                .onDrag { draggedSetVideoId = sv; return NSItemProvider(object: sv as NSString) }
                                .onDrop(of: [UTType.text],
                                        delegate: TrackReorderDropDelegate(targetSetVideoId: sv, playlist: playlist, vm: vm, draggedSetVideoId: $draggedSetVideoId))
                        } else {
                            row
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    /// Match the row to nowPlaying by title. Accessed via the env object
    /// so SwiftUI re-renders this view tree when the current track changes.
    private func isCurrentTrack(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }

    @ViewBuilder
    private func trackContextMenu(for t: NativeShellViewModel.TrackSummary) -> some View {
        Button { vm.playTrack(t) } label: { Label(L10n.t("transport.play"), systemImage: "play.fill") }
        Button { vm.addToQueue(track: t, playNext: true) } label: {
            Label(L10n.t("shell.queue.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { vm.addToQueue(track: t) } label: { Label(L10n.t("shell.queue.add"), systemImage: "text.append") }
        Button { vm.startRadio(t) } label: {
            Label(L10n.t("shell.action.startRadio"), systemImage: "dot.radiowaves.left.and.right")
        }
        Button { vm.startSimilarPlaylist(seed: t) } label: {
            Label(L10n.t("shell.action.similarPlaylist"), systemImage: "square.stack.3d.up")
        }
                Divider()
        Menu {
            Button { vm.beginCreatePlaylist(addingVideoId: t.id) } label: {
                Label(L10n.t("shell.playlist.createNew"), systemImage: "plus")
            }
            if !vm.playlists.isEmpty { Divider() }
            ForEach(vm.playlists) { p in
                Button(p.title) {
                    vm.addToPlaylist(videoId: t.id,
                                     playlistId: p.id,
                                     trackTitle: t.title,
                                     playlistTitle: p.title)
                }
            }
        } label: { Label(L10n.t("shell.playlist.addTo"), systemImage: "plus") }
        Button { vm.likeTrack(videoId: t.id, title: t.title) } label: {
            Label(L10n.t("shell.action.saveToLiked"), systemImage: "heart")
        }
        Button { vm.dislikeTrack(videoId: t.id, title: t.title) } label: {
            Label(L10n.t("shell.action.dislike"), systemImage: "hand.thumbsdown")
        }
        Divider()
        if let aid = t.artistId {
            Button { vm.openArtist(browseId: aid, name: t.artist) } label: {
                Label(L10n.t("shell.action.goToArtist"), systemImage: "music.mic")
            }
        }
        if let alid = t.albumId {
            Button { vm.openAlbum(albumId: alid, title: t.album ?? "", thumbnailURL: t.thumbnailURL) } label: {
                Label(L10n.t("shell.action.goToAlbum"), systemImage: "opticaldisc")
            }
        }
        if vm.isEditablePlaylist(playlist) {
            Divider()
            Button(role: .destructive) {
                vm.removeFromPlaylist(tracks: [t], from: playlist)
            } label: { Label(L10n.t("shell.playlist.removeFrom"), systemImage: "minus.circle") }
        }
        Divider()
        Button { vm.copyLink(videoId: t.id) } label: { Label(L10n.t("shell.action.copyLink"), systemImage: "link") }
        Button { vm.openInBrowser(videoId: t.id) } label: { Label(L10n.t("shell.action.openInBrowser"), systemImage: "safari") }
    }
}

/// Drag-to-reorder delegate for editable-playlist track rows. Reorders live
/// (local) as the drag passes over rows; commits the move to the server on drop.
private struct TrackReorderDropDelegate: DropDelegate {
    let targetSetVideoId: String
    let playlist: NativeShellViewModel.PlaylistSummary
    let vm: NativeShellViewModel
    @Binding var draggedSetVideoId: String?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedSetVideoId, dragged != targetSetVideoId else { return }
        Task { @MainActor in vm.localMoveTrack(fromSetVideoId: dragged, toSetVideoId: targetSetVideoId) }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let dragged = draggedSetVideoId {
            Task { @MainActor in vm.commitTrackMove(setVideoId: dragged, in: playlist) }
        }
        draggedSetVideoId = nil
        return true
    }
}

private struct TrackRow: View {
    let index: Int
    let track: NativeShellViewModel.TrackSummary
    let isPlaying: Bool
    let zebra: Bool
    var showAlbum: Bool = false
    var selected: Bool = false
    /// Used when the track has no per-row artwork (album tracks share the
    /// album cover instead of shipping one thumbnail each).
    var fallbackThumbnailURL: String? = nil
    /// Only the now-playing row whose track has a music-video counterpart
    /// shows the clip icon (hasVideo is known only for the current track).
    var showClipIcon: Bool = false
    var onClip: (() -> Void)? = nil

    @State private var isHovered: Bool = false

    /// Background tint: selection wins, then hover, then isPlaying, then zebra.
    private var rowBackground: Color {
        if selected { return Color.accentColor.opacity(0.28) }
        if isHovered { return Color.primary.opacity(0.08) }
        if isPlaying { return Color.accentColor.opacity(0.18) }
        return zebra ? Color.primary.opacity(0.03) : .clear
    }

    private var titleColor: Color {
        isPlaying ? Color.accentColor : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            // Index column — replaced by a speaker icon for the playing row
            // so it's obvious at a glance, like Spotify.
            ZStack {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.accentColor)
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.7))
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.4))
                }
            }
            .frame(width: 28, alignment: .trailing)

            // Title column: artwork + title/artist. Flexible so it aligns
            // with the title column header.
            HStack(spacing: 12) {
                cover
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showAlbum {
                Text(track.album ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showClipIcon {
                Button(action: { onClip?() }) {
                    Image(systemName: "film")
                        .font(.system(size: 12))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("shell.action.playClip"))
            }

            Text(track.duration ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.5))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    /// Track artwork; falls back to the album/playlist cover when the row
    /// itself ships no thumbnail (album tracks), with a music-note placeholder
    /// as the last resort so it never looks empty.
    private var effectiveThumbnailURL: String? {
        if let s = track.thumbnailURL, !s.isEmpty { return s }
        if let f = fallbackThumbnailURL, !f.isEmpty { return f }
        return nil
    }

    @ViewBuilder
    private var cover: some View {
        if let s = effectiveThumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.primary.opacity(0.06)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.3))
            )
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @EnvironmentObject private var media: MediaController
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var prefs = Preferences.shared
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel

    // Local display state for the progress slider. Updated event-driven
    // from MediaController + a 0.5s tick timer between updates so it
    // doesn't visibly stall waiting for the 4s safety-net poll.
    @State private var displayedTime: Double = 0
    @State private var isDragging: Bool = false
    @State private var artworkHovered: Bool = false

    /// Active-control tint — follows the selected theme's accent.
    private var activeTint: Color { prefs.theme.accentColor }

    private let tickTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 16) {
            leftSection
                .frame(maxWidth: .infinity, alignment: .leading)
            centerSection
                .frame(maxWidth: 620)
            rightSection
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(bg)
        .onAppear { displayedTime = clock.time }
        .onChange(of: clock.time) { newValue in
            if !isDragging { displayedTime = newValue }
        }
        .onChange(of: media.nowPlaying.title) { _ in
            if !isDragging { displayedTime = clock.time }
        }
        .onReceive(tickTimer) { _ in
            guard !isDragging, media.nowPlaying.isPlaying else { return }
            let total = media.nowPlaying.duration
            displayedTime = min(displayedTime + 0.5, total > 0 ? total : displayedTime + 0.5)
        }
    }

    // MARK: Left — artwork + track info + add

    private var leftSection: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : L10n.t("shell.player.notPlaying"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Button(action: {
                    let a = media.nowPlaying.artist
                    if !a.isEmpty { vm.openArtistByName(a) }
                }) {
                    Text(media.nowPlaying.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.55))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("shell.action.goToArtist"))
                .disabled(media.nowPlaying.artist.isEmpty)
            }
            addButton
            Spacer(minLength: 0)
        }
        .contextMenu { nowPlayingMenu }
    }

    /// Right-click menu for the currently-playing track in the player bar —
    /// mirrors the list-row actions against `media.nowPlaying` (which only
    /// carries videoId/title/artist/artwork, so no go-to-album here).
    @ViewBuilder
    private var nowPlayingMenu: some View {
        let np = media.nowPlaying
        if np.hasTrack, !np.videoId.isEmpty {
            let t = NativeShellViewModel.TrackSummary(
                id: np.videoId, title: np.title, artist: np.artist,
                duration: nil, thumbnailURL: np.artworkURL)
            Button { vm.startRadio(t) } label: {
                Label(L10n.t("shell.action.startRadio"), systemImage: "dot.radiowaves.left.and.right")
            }
            Button { vm.startSimilarPlaylist(seed: t) } label: {
                Label(L10n.t("shell.action.similarPlaylist"), systemImage: "square.stack.3d.up")
            }
                        if !np.artist.isEmpty {
                Button { vm.openArtistByName(np.artist) } label: {
                    Label(L10n.t("shell.action.goToArtist"), systemImage: "music.mic")
                }
            }
            Divider()
            Menu {
                Button { vm.beginCreatePlaylist(addingVideoId: np.videoId) } label: {
                    Label(L10n.t("shell.playlist.createNew"), systemImage: "plus")
                }
                if !vm.playlists.isEmpty { Divider() }
                ForEach(vm.playlists) { p in
                    Button(p.title) {
                        vm.addToPlaylist(videoId: np.videoId, playlistId: p.id,
                                         trackTitle: np.title, playlistTitle: p.title)
                    }
                }
            } label: { Label(L10n.t("shell.playlist.addTo"), systemImage: "plus") }
            Button { media.run("like") } label: {
                Label(L10n.t(np.liked ? "transport.unlike" : "transport.like"),
                      systemImage: np.liked ? "heart.fill" : "heart")
            }
            Divider()
            Button { vm.copyLink(videoId: np.videoId) } label: {
                Label(L10n.t("shell.action.copyLink"), systemImage: "link")
            }
            Button { vm.openInBrowser(videoId: np.videoId) } label: {
                Label(L10n.t("shell.action.openInBrowser"), systemImage: "safari")
            }
        }
    }

    private var addButton: some View {
        Button(action: {
            guard media.nowPlaying.hasTrack else { return }
            media.run("like")
        }) {
            Image(systemName: media.nowPlaying.liked ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(media.nowPlaying.liked ? activeTint : .primary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(!media.nowPlaying.hasTrack)
        .help(L10n.t("shell.action.saveToLiked"))
    }

    // MARK: Center — transport + progress

    private var centerSection: some View {
        VStack(spacing: 5) {
            transport
            progressRow
        }
    }

    private var transport: some View {
        HStack(spacing: 20) {
            shuffleButton
            sideButton("backward.fill") { media.run("prev") }
            playButton
            sideButton("forward.fill") { media.run("next") }
            repeatButton
        }
    }

    private var shuffleButton: some View {
        Button(action: { media.run("shuffle") }) {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(media.nowPlaying.shuffle ? activeTint : .primary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.action.shuffle"))
    }

    private var repeatButton: some View {
        let mode = media.nowPlaying.repeatMode
        return Button(action: { media.run("repeat") }) {
            Image(systemName: mode == "ONE" ? "repeat.1" : "repeat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mode == "NONE" ? .primary.opacity(0.6) : activeTint)
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.action.repeat"))
    }

    private var playButton: some View {
        Button(action: { media.run("playpause") }) {
            Image(systemName: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(prefs.theme.baseColor) // punches through the knob
                .frame(width: 34, height: 34)
                .background(Color.primary) // white on dark themes, dark on light
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func sideButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary.opacity(0.9))
        }
        .buttonStyle(.plain)
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(format(displayedTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
            Slider(
                value: $displayedTime,
                in: 0...max(media.nowPlaying.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        media.run("seek", value: displayedTime)
                    }
                }
            )
            .controlSize(.mini)
            Text(format(media.nowPlaying.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary.opacity(0.6))
                .frame(width: 36, alignment: .leading)
        }
    }

    // MARK: Right — lyrics + queue + sleep timer + volume

    private var rightSection: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            themeToggle
            lyricsToggle
            queueToggle
            SleepTimerControl()
            VolumeControl()
                .environmentObject(media)
        }
    }

    private var themeToggle: some View {
        Button(action: { vm.toggleThemePicker() }) {
            Image(systemName: "paintpalette")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.isThemePickerVisible ? .primary : .primary.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(vm.isThemePickerVisible ? Color.primary.opacity(0.15) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.theme.title"))
    }

    private var lyricsToggle: some View {
        Button(action: { vm.toggleLyrics() }) {
            Image(systemName: "text.quote")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.isLyricsVisible ? .primary : .primary.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(vm.isLyricsVisible ? Color.primary.opacity(0.15) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.lyrics.toggleHelp"))
    }

    private var queueToggle: some View {
        Button(action: { vm.toggleQueue() }) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(vm.isQueueVisible ? .primary : .primary.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(vm.isQueueVisible ? Color.primary.opacity(0.15) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.queue.toggleHelp"))
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var artwork: some View {
        Group {
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                raised.overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundColor(.primary.opacity(0.35))
                )
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .center) {
            if artworkHovered && media.nowPlaying.hasTrack {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .onHover { artworkHovered = $0 }
        .onTapGesture { if media.nowPlaying.hasTrack { vm.toggleNowPlaying() } }
        .help(L10n.t("shell.player.nowPlayingHelp"))
    }
}

// MARK: - Lyrics side panel

private struct LyricsPanel: View {
    let bg: Color
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.primary.opacity(0.08))
            content
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(bg)
        .onAppear { vm.loadLyricsForCurrentTrack() }
        .onChange(of: media.nowPlaying.videoId) { _ in
            vm.loadLyricsForCurrentTrack()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("shell.lyrics.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { vm.toggleLyrics() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            if media.nowPlaying.hasTrack {
                Text(media.nowPlaying.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                Text(media.nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if vm.lyricsLoading && vm.lyrics == nil {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("shell.lyrics.loading"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = vm.lyrics {
            LyricsCrawlView(lyrics: lyrics, textColor: .primary.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
        } else if let msg = vm.lyricsError {
            VStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.primary.opacity(0.3))
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.primary.opacity(0.3))
                Text(L10n.t("shell.lyrics.noTrack"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Theme picker side panel

private struct ThemePanel: View {
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.primary.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(L10n.t("shell.theme.light"))
                    ForEach(Theme.allCases.filter { !$0.isDark }) { row($0) }
                    sectionLabel(L10n.t("shell.theme.dark"))
                    ForEach(Theme.allCases.filter { $0.isDark }) { row($0) }
                }
                .padding(10)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased(with: L10n.locale))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.primary.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var header: some View {
        HStack {
            Text(L10n.t("shell.theme.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { vm.toggleThemePicker() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func row(_ theme: Theme) -> some View {
        let active = prefs.theme == theme
        return Button(action: { prefs.theme = theme }) {
            HStack(spacing: 10) {
                swatch(theme)
                Text(theme.displayName)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(theme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live 3-stripe preview: app bg · surface · accent.
    private func swatch(_ theme: Theme) -> some View {
        HStack(spacing: 0) {
            theme.baseColor
            theme.surfaceColor
            theme.accentColor
        }
        .frame(width: 46, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Volume + Sleep timer

private struct VolumeControl: View {
    @EnvironmentObject private var media: MediaController
    @State private var isDragging: Bool = false
    /// Local copy so the slider tracks user drag immediately. Kept in
    /// sync with the bridge's reported volume on every nowPlaying push.
    @State private var localVolume: Double = 1
    /// Volume to restore when un-muting via the speaker icon.
    @State private var preMuteVolume: Double = 1

    private var speakerIcon: String {
        if localVolume <= 0 { return "speaker.slash.fill" }
        if localVolume < 0.33 { return "speaker.fill" }
        if localVolume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleMute) {
                Image(systemName: speakerIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .help(L10n.t("shell.volume.mute"))
            Slider(value: $localVolume, in: 0...1) { editing in
                isDragging = editing
                if !editing { media.run("volume", value: localVolume) }
            }
            .controlSize(.mini)
            .frame(width: 80)
        }
        .onAppear { localVolume = media.nowPlaying.volume }
        .onChange(of: media.nowPlaying.volume) { newValue in
            // Only follow the bridge while the user isn't dragging — the
            // editing-ended handler owns the final write.
            if !isDragging { localVolume = newValue }
        }
    }

    private func toggleMute() {
        if localVolume > 0 {
            preMuteVolume = localVolume
            localVolume = 0
        } else {
            localVolume = preMuteVolume > 0 ? preMuteVolume : 1
        }
        media.run("volume", value: localVolume)
    }
}

private struct SleepTimerControl: View {
    @StateObject private var sleep = SleepTimer.shared
    @State private var showMenu: Bool = false

    private struct Option: Identifiable {
        /// Label-keyed rather than a fresh UUID: `options` is now computed
        /// (it reads the catalog), so a random id would churn ForEach
        /// identity on every render.
        var id: String { label }
        let label: String
        let mode: SleepTimer.Mode
    }

    private var options: [Option] {
        [
            .init(label: L10n.plural("shell.sleep.minutes", 5),  mode: .duration(5 * 60)),
            .init(label: L10n.plural("shell.sleep.minutes", 15), mode: .duration(15 * 60)),
            .init(label: L10n.plural("shell.sleep.minutes", 30), mode: .duration(30 * 60)),
            .init(label: L10n.plural("shell.sleep.hours", 1),    mode: .duration(60 * 60)),
            .init(label: L10n.t("shell.sleep.endOfTrack"),       mode: .endOfTrack)
        ]
    }

    private var iconName: String {
        sleep.isActive ? "moon.fill" : "moon"
    }

    private var countdownLabel: String? {
        if let r = sleep.remaining, sleep.isActive {
            let mm = Int(r) / 60
            let ss = Int(r) % 60
            return String(format: "%d:%02d", mm, ss)
        }
        if case .endOfTrack? = sleep.mode { return L10n.t("shell.sleep.eot") }
        return nil
    }

    var body: some View {
        Button(action: { showMenu.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                if let label = countdownLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundColor(sleep.isActive ? .accentColor : .primary.opacity(0.85))
            .padding(.horizontal, sleep.isActive ? 8 : 0)
            .frame(height: 30)
            .frame(minWidth: 30)
            .background(showMenu ? Color.primary.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.t("shell.sleep.title"))
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("shell.sleep.header"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(.primary.opacity(0.55))
                    .padding(.bottom, 4)
                ForEach(options) { opt in
                    Button(action: {
                        sleep.start(opt.mode)
                        showMenu = false
                    }) {
                        Text(opt.label)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.0001))
                    }
                    .buttonStyle(.plain)
                }
                if sleep.isActive {
                    Divider().background(Color.primary.opacity(0.1)).padding(.vertical, 2)
                    Button(action: {
                        sleep.cancel()
                        showMenu = false
                    }) {
                        Text(L10n.t("common.cancel"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(width: 200)
        }
    }
}

// MARK: - Queue panel

/// Drag-to-reorder delegate for ownQueue rows. Reorders live as the drag
/// passes over each row; clears the drag state on drop.
private struct OwnQueueDropDelegate: DropDelegate {
    let targetId: UUID
    let vm: NativeShellViewModel
    @Binding var draggedId: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedId, dragged != targetId else { return }
        Task { @MainActor in vm.moveOwnQueueItem(fromId: dragged, toId: targetId) }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }
}

private struct QueuePanel: View {
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController
    @State private var draggedId: UUID?

    /// Highlight the queue row that matches what's ACTUALLY playing (the
    /// player bar / nowPlaying), not YT's DOM "selected" index — those two
    /// can drift apart, which is the "playing one vs shown one" mismatch.
    private func isCurrentQueueItem(_ item: NativeShellViewModel.QueueItem) -> Bool {
        let np = media.nowPlaying
        guard np.hasTrack else { return false }
        if let vid = item.videoId, !vid.isEmpty, !np.videoId.isEmpty {
            return vid == np.videoId
        }
        return item.title.caseInsensitiveCompare(np.title) == .orderedSame
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.primary.opacity(0.08))
            content
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    private var header: some View {
        HStack {
            Text(L10n.t("shell.queue.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            if !vm.queue.isEmpty {
                Text("\(vm.queue.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.4))
            }
            Button(action: { vm.toggleQueue() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if vm.queue.isEmpty && vm.ownQueue.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.primary.opacity(0.3))
                Text(L10n.t("shell.queue.empty"))
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.45))
                Text(L10n.t("shell.queue.emptyHint"))
                    .font(.system(size: 10))
                    .foregroundColor(.primary.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !vm.ownQueue.isEmpty {
                        ownQueueHeader
                        ForEach(vm.ownQueue) { item in
                            Button(action: { vm.playOwnQueueItem(item) }) {
                                OwnQueueRow(item: item, raised: raised)
                                    .opacity(draggedId == item.id ? 0.4 : 1)
                            }
                            .buttonStyle(.plain)
                            .onDrag {
                                draggedId = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text],
                                    delegate: OwnQueueDropDelegate(targetId: item.id, vm: vm, draggedId: $draggedId))
                            .contextMenu {
                                Button(L10n.t("shell.queue.playNow")) { vm.playOwnQueueItem(item) }
                                Button(L10n.t("shell.action.remove")) { vm.removeFromOwnQueue(item) }
                            }
                        }
                        Divider().background(Color.primary.opacity(0.1))
                            .padding(.vertical, 6)
                    }
                    ForEach(vm.queue) { item in
                        Button(action: { vm.jumpToQueueIndex(item.id) }) {
                            QueueRow(item: item, raised: raised, isPlaying: isCurrentQueueItem(item))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { queueContextMenu(for: item) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }

    private var ownQueueHeader: some View {
        HStack {
            Text(L10n.t("shell.queue.upNext"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.primary.opacity(0.5))
            Spacer()
            Button(action: { vm.clearOwnQueue() }) {
                Text(L10n.t("shell.action.clear"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func queueContextMenu(for item: NativeShellViewModel.QueueItem) -> some View {
        Button(L10n.t("shell.queue.jumpTo")) { vm.jumpToQueueIndex(item.id) }
        if let vid = item.videoId {
            Divider()
            Button(L10n.t("transport.like")) { vm.likeTrack(videoId: vid, title: item.title) }
            Button(L10n.t("shell.action.dislike")) { vm.dislikeTrack(videoId: vid, title: item.title) }
            Divider()
            Menu(L10n.t("shell.playlist.addTo")) {
                if vm.playlists.isEmpty {
                    Text(L10n.t("shell.playlists.loading"))
                } else {
                    ForEach(vm.playlists) { p in
                        Button(p.title) {
                            vm.addToPlaylist(videoId: vid,
                                             playlistId: p.id,
                                             trackTitle: item.title,
                                             playlistTitle: p.title)
                        }
                    }
                }
            }
            Divider()
            Button(L10n.t("shell.action.openInBrowser")) { vm.openInBrowser(videoId: vid) }
        }
    }
}

/// Visually distinct from QueueRow so the user can tell at a glance
/// which items are theirs ("Up next") versus YT's autoplay context.
private struct OwnQueueRow: View {
    let item: NativeShellViewModel.OwnQueueItem
    let raised: Color
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            cover
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.artist.isEmpty ? L10n.t("shell.queue.manual") : item.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.primary.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentColor.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = item.thumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    raised
                }
            }
        } else {
            raised
        }
    }
}

private struct QueueRow: View {
    let item: NativeShellViewModel.QueueItem
    let raised: Color
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            cover
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .green : .primary)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.primary.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isPlaying ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cover: some View {
        if let s = item.thumbnailURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    raised
                }
            }
        } else {
            raised
        }
    }
}
