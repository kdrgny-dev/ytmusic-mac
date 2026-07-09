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

            if vm.isSearchVisible {
                SearchOverlay(vm: vm)
                    .environment(\.colorScheme, .dark) // dark HUD on any theme
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            }

            if vm.isCreatePlaylistVisible {
                CreatePlaylistOverlay(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
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
        .animation(.easeInOut(duration: 0.18), value: vm.isSearchVisible)
        .animation(.easeInOut(duration: 0.18), value: vm.isCreatePlaylistVisible)
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
            Text("Yeni sürüm var: v\(update.version)")
                .font(.system(size: 12, weight: .semibold))
            if let notes = update.notes {
                Text(notes)
                    .font(.system(size: 12))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button(action: { NSWorkspace.shared.open(update.downloadURL) }) {
                Text("İndir")
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
            .help("Bu sürümü atla")
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

private struct SearchOverlay: View {
    @ObservedObject var vm: NativeShellViewModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Dim backdrop — tap outside the card to dismiss.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { vm.toggleSearch() }

            VStack(spacing: 0) {
                searchField
                Divider().background(Color.primary.opacity(0.08))
                tabBar
                Divider().background(Color.primary.opacity(0.08))
                resultsArea
            }
            .frame(maxWidth: 680)
            .frame(maxHeight: 560)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
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
            TextField("Şarkı, sanatçı, albüm, çalma listesi ara…", text: $vm.searchQuery)
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
            Button(action: { vm.toggleSearch() }) {
                Text("⎋")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
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
                    Text("\(vm.searchTab.label.lowercased()) aramak için yaz")
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
            Text("ÖNERİLER")
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
                    Text("SON ARAMALAR")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(.primary.opacity(0.5))
                    Spacer()
                    Button("Temizle") { vm.clearSearchHistory() }
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
                Text("\(trackCount) şarkı")
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
            .init(id: "home",    icon: "house.fill",            label: "Ana sayfa",    action: { vm.goHome() }),
            .init(id: "explore", icon: "safari",                label: "Keşfet", action: { vm.goExplore() }),
            .init(id: "search",  icon: "magnifyingglass",       label: "Ara",  action: { vm.toggleSearch() }),
            .init(id: "history", icon: "clock.arrow.circlepath", label: "Geçmiş", action: { vm.goHistory() })
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
                    sectionHeader("Keşfet")
                    ForEach(topItems) { item in
                        Button(action: item.action) {
                            sidebarRow(icon: item.icon, label: item.label, active: isTopActive(item.id))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        sectionHeader("Çalma listelerin")
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
                        sectionHeader("Sanatçılar").padding(.top, 18)
                        ForEach(vm.followedArtists) { a in
                            Button(action: { vm.openArtist(browseId: a.id, name: a.title) }) {
                                playlistRow(a, circular: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !vm.savedAlbums.isEmpty {
                        sectionHeader("Albümler").padding(.top, 18)
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
                        .help(vm.isNowPlayingCollection(p) ? "\(p.title) — şu an çalıyor" : p.title)
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
        .help(prefs.sidebarCollapsed ? "Kenar çubuğunu genişlet" : "Kenar çubuğunu daralt")
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
        .help("Yeni çalma listesi")
    }

    @ViewBuilder
    private var playlistSection: some View {
        if vm.loadingPlaylists && vm.playlists.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text("Yükleniyor…")
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
        Button { vm.openPlaylist(p) } label: { Label("Aç", systemImage: "arrow.right.circle") }
        if vm.isEditablePlaylist(p) {
            Button { vm.beginRename(p) } label: { Label("Adını değiştir", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { vm.beginDelete(p) } label: { Label("Sil", systemImage: "trash") }
        } else {
            Button { vm.removePlaylistFromLibrary(p) } label: {
                Label("Kitaplıktan çıkar", systemImage: "minus.circle")
            }
        }
        Divider()
        Button { vm.copyPlaylistLink(p) } label: { Label("Bağlantıyı kopyala", systemImage: "link") }
        if vm.hasCustomPlaylistOrder {
            Button { vm.resetPlaylistOrder() } label: {
                Label("Sıralamayı sıfırla", systemImage: "arrow.up.arrow.down")
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
        case "history": return vm.mainSection == .history
        case "search":  return vm.isSearchVisible
        default:        return false
        }
    }

    private func isPlaylistActive(_ p: NativeShellViewModel.PlaylistSummary) -> Bool {
        vm.mainSection == .playlist(p)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
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
                    .help("Şu an bu listeden çalıyor")
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
                Text("Yeni çalma listesi")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                HStack(alignment: .top, spacing: 16) {
                    coverWell
                    VStack(alignment: .leading, spacing: 10) {
                        field("Liste adı", text: $name)
                            .focused($nameFocused)
                        field("Açıklama (opsiyonel)", text: $desc)
                        privacyPicker
                    }
                }

                Text("Not: kapak görseli YT'nin oluşturma API'sinde desteklenmiyor — liste, parçalardan otomatik kapak alır.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button("İptal") { vm.cancelCreatePlaylist() }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.createPlaylist(title: name, description: desc, privacy: privacy) }) {
                        Text("Oluştur")
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
                        Text("Kapak seç")
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
                Text("Adını değiştir")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                TextField("Liste adı", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))
                    .onSubmit { if canSave { vm.renamePlaylist(playlist, to: name) } }
                HStack(spacing: 10) {
                    Spacer()
                    Button("İptal") { vm.cancelRename() }
                        .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.renamePlaylist(playlist, to: name) }) {
                        Text("Kaydet")
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
                Text("Çalma listesini sil?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("“\(playlist.title)” kalıcı olarak silinecek. Bu işlem geri alınamaz.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    Button("İptal") { vm.cancelDelete() }
                        .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    Button(action: { vm.confirmDeletePlaylist() }) {
                        Text("Sil")
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
            case .history:
                HistoryView(vm: vm)
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
            Text("Bir çalma listesi seç ya da Ana sayfayı aç")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text("Öneriler için Kenar çubuğu → Ana sayfa.")
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
                   help: "Geri (⌘ ←)") { vm.goBack() }
            button(systemName: "chevron.right",
                   enabled: vm.canGoForward,
                   help: "İleri (⌘ →)") { vm.goForward() }
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
                            title: "Albümler",
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
                            title: "Single'lar",
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
                Text("SANATÇI")
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
                Text("Popüler şarkılar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if let bid = a.allSongsBrowseId {
                    Button("Tüm şarkılar") {
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
        let np = media.nowPlaying
        return np.hasTrack && np.title.caseInsensitiveCompare(t.title) == .orderedSame
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
                Text("KİTAPLIK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text("Geçmiş")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("Son dinlediklerin, YT Music'in gün gruplarıyla")
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
            .help("Geçmişi yenile")
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
                    Label("Aç", systemImage: "arrow.right.circle")
                }
                Button { vm.openPlaylist(p, autoplay: true) } label: {
                    Label("Oynat", systemImage: "play.fill")
                }
                Divider()
                if vm.isPlaylistSaved(p) {
                    Button { vm.removePlaylistFromLibrary(p) } label: {
                        Label("Kitaplıktan çıkar", systemImage: "minus.circle")
                    }
                } else {
                    Button { vm.savePlaylistToLibrary(p) } label: {
                        Label("Kitaplığa kaydet", systemImage: "plus.circle")
                    }
                }
                Divider()
                Button { vm.copyPlaylistLink(p) } label: {
                    Label("Bağlantıyı kopyala", systemImage: "link")
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
                Text("KATEGORİ")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text(vm.categoryTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                if !vm.categoryPlaylists.isEmpty {
                    Text("\(vm.categoryPlaylists.count) çalma listesi")
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
                    .help("Kitaplığında kayıtlı")
            }
            if let n = playlist.trackCount {
                Text("\(n) şarkı")
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
            .help("Kitaplığında kayıtlı")
    }
}

/// Track count sits ON the artwork, so it needs its own scrim — YT covers
/// range from near-white to near-black.
private struct CountBadge: View {
    let count: Int
    let compact: Bool

    var body: some View {
        Text(compact ? "\(count)" : "\(count) şarkı")
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .padding(compact ? 5 : 7)
            .help("\(count) şarkı")
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
                Text("Sana özel öneriler")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("YT Music'in senin için karıştırdığı playlist'ler, sanatçılar ve türler")
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
            .help("Yenile")
        }
    }

    /// Greeting changes through the day so home doesn't feel static
    /// across long sessions. No name yet — we don't fetch user identity.
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "GÜNAYDIN"
        case 12..<18: return "İYİ GÜNLER"
        case 18..<23: return "İYİ AKŞAMLAR"
        default:      return "İYİ GECELER"
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
            Button("Yeniden dene") { vm.reloadHome() }
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
                        sectionLabel("Yeni çıkanlar")
                        ForEach(vm.exploreNewReleases) { ShelfRow(shelf: $0, vm: vm) }
                    }
                    if !vm.exploreCharts.isEmpty {
                        sectionLabel("Listeler")
                        ForEach(vm.exploreCharts) { ChartSectionView(section: $0, vm: vm) }
                    }
                    if !vm.genreSections.isEmpty {
                        sectionLabel("Türler & ruh hâlleri")
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
                Text("KEŞFET")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text("Keşfet")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("Yeni çıkanlar, listeler ve türler")
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
            .help("Yenile")
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
            Button("Yeniden dene") { vm.reloadExplore() }
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
                        Button { vm.playTrack(track) } label: { Label("Oynat", systemImage: "play.fill") }
                        Button { vm.addToQueue(track: track, playNext: true) } label: {
                            Label("Sıradaki olarak çal", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button { vm.addToQueue(track: track) } label: { Label("Kuyruğa ekle", systemImage: "text.append") }
                        Button { vm.startRadio(track) } label: {
                            Label("Radyo başlat", systemImage: "dot.radiowaves.left.and.right")
                        }
                        Divider()
                        Menu {
                            Button { vm.beginCreatePlaylist(addingVideoId: track.id) } label: {
                                Label("Yeni liste oluştur", systemImage: "plus")
                            }
                            if !vm.playlists.isEmpty { Divider() }
                            ForEach(vm.playlists) { p in
                                Button(p.title) {
                                    vm.addToPlaylist(videoId: track.id, playlistId: p.id,
                                                     trackTitle: track.title, playlistTitle: p.title)
                                }
                            }
                        } label: { Label("Çalma listesine ekle", systemImage: "plus") }
                        Button { vm.likeTrack(videoId: track.id, title: track.title) } label: {
                            Label("Beğenilenlere kaydet", systemImage: "heart")
                        }
                        Button { vm.openInBrowser(videoId: track.id) } label: { Label("Tarayıcıda aç", systemImage: "safari") }
                    }
                }
            }
        }
    }

    private func isCurrent(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        let np = media.nowPlaying
        return np.hasTrack && np.title.caseInsensitiveCompare(t.title) == .orderedSame
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

/// Shared right-click menu for a HomeCard (used by Home/Explore shelves and
/// the artist page's album/single carousels). Actions depend on card kind.
@MainActor @ViewBuilder
private func homeCardContextMenu(_ card: NativeShellViewModel.HomeCard,
                                 _ vm: NativeShellViewModel) -> some View {
    switch card.kind {
    case .song:
        let t = NativeShellViewModel.TrackSummary(
            id: card.id, title: card.title, artist: card.subtitle,
            duration: nil, thumbnailURL: card.thumbnailURL)
        Button { vm.openHomeCard(card) } label: { Label("Oynat", systemImage: "play.fill") }
        Button { vm.addToQueue(track: t, playNext: true) } label: {
            Label("Sıradaki olarak çal", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { vm.addToQueue(track: t) } label: { Label("Kuyruğa ekle", systemImage: "text.append") }
        Divider()
        Menu {
            Button { vm.beginCreatePlaylist(addingVideoId: card.id) } label: {
                Label("Yeni liste oluştur", systemImage: "plus")
            }
            if !vm.playlists.isEmpty { Divider() }
            ForEach(vm.playlists) { p in
                Button(p.title) {
                    vm.addToPlaylist(videoId: card.id, playlistId: p.id,
                                     trackTitle: card.title, playlistTitle: p.title)
                }
            }
        } label: { Label("Çalma listesine ekle", systemImage: "plus") }
        Button { vm.likeTrack(videoId: card.id, title: card.title) } label: {
            Label("Beğenilenlere kaydet", systemImage: "heart")
        }
        Divider()
        Button { vm.copyLink(videoId: card.id) } label: { Label("Bağlantıyı kopyala", systemImage: "link") }
        Button { vm.openInBrowser(videoId: card.id) } label: { Label("Tarayıcıda aç", systemImage: "safari") }
    case .playlist, .album:
        let p = NativeShellViewModel.PlaylistSummary(
            id: card.id, title: card.title, thumbnailURL: card.thumbnailURL)
        Button { vm.playHomeCard(card) } label: { Label("Çal", systemImage: "play.fill") }
        Button { vm.addCollectionToQueue(id: card.id, title: card.title) } label: {
            Label("Kuyruğa ekle", systemImage: "text.append")
        }
        Button { vm.openHomeCard(card) } label: { Label("Aç", systemImage: "arrow.right.circle") }
        Button { vm.savePlaylistToLibrary(p) } label: {
            Label("Kitaplığa kaydet", systemImage: "plus.circle")
        }
        Button { vm.copyPlaylistLink(p) } label: { Label("Bağlantıyı kopyala", systemImage: "link") }
    case .artist:
        Button { vm.openArtist(browseId: card.id, name: card.title) } label: {
            Label("Sanatçıya git", systemImage: "music.mic")
        }
    }
}

/// One reusable carousel row used by every horizontal section on Home.
/// Header (title + optional strapline) on the left, paired chevron pills
/// on the right of the same row. Chevrons stay visible (no hover) and
/// fade their fill when there's no further scroll in that direction.
private struct CarouselSection<Item: Identifiable, Content: View>: View where Item.ID: Hashable {
    let title: String
    let subtitle: String?
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
                    Text(s.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.primary.opacity(0.5))
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            Spacer()
            if needsScroll {
                navChevron(.leftward, proxy: proxy)
                navChevron(.rightward, proxy: proxy)
            }
        }
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
private struct GenreCarousel: View {
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

private struct HomeCardView: View {
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
            Text("\(selectedIDs.count) seçili")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button("Tümünü seç") { selectAll() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.7))
            Menu {
                Button { vm.beginCreatePlaylist(addingVideoIds: selectedVideoIds()); clearSelection() } label: {
                    Label("Yeni liste oluştur", systemImage: "plus")
                }
                if !vm.playlists.isEmpty { Divider() }
                ForEach(vm.playlists) { p in
                    Button(p.title) {
                        vm.addTracksToPlaylist(videoIds: selectedVideoIds(), playlistId: p.id, playlistTitle: p.title)
                        clearSelection()
                    }
                }
            } label: {
                Label("Çalma listesine ekle", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if vm.isEditablePlaylist(playlist) {
                Button("Listeden çıkar") {
                    vm.removeFromPlaylist(tracks: displayedTracks.filter { selectedIDs.contains($0.id) }, from: playlist)
                    clearSelection()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.red.opacity(0.9))
            }
            Button("Temizle") { clearSelection() }
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
                TextField("Listede ara", text: $searchText)
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
                Text("\(displayedTracks.count) sonuç")
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
            sortHeader(field: .title) { Text("Başlık") }
                .frame(maxWidth: .infinity, alignment: .leading)
            if showAlbumColumn {
                sortHeader(field: .album) { Text("Albüm") }
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
    /// MPRE… / OLAK… are YT's album id namespaces.
    private var kindLabel: String {
        let id = playlist.id
        if id.hasPrefix("MPRE") || id.hasPrefix("OLAK") { return "ALBUM" }
        if id.hasPrefix("VLPL") || id.hasPrefix("VLRDA") { return "PLAYLIST" }
        return "PLAYLIST"
    }

    private var isAlbum: Bool { kindLabel == "ALBUM" }

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

    private var playButton: some View {
        Button(action: { vm.playPlaylist(displayedTracks) }) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(prefs.theme.isDark ? .black : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accentGreen))
        }
        .buttonStyle(.plain)
        .help("Oynat")
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
        .help("Karıştır")
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
        .help("Tümünü kuyruğa ekle")
    }

    private var albumSaveButton: some View {
        Button(action: { vm.toggleAlbumSaved() }) {
            HStack(spacing: 6) {
                Image(systemName: vm.isAlbumSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 13))
                Text(vm.isAlbumSaved ? "Kaydedildi" : "Kaydet")
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
        .help(vm.isAlbumSaved ? "Kitaplıktan çıkar" : "Albümü kitaplığa kaydet")
    }

    /// "98 tracks · 5h 32min" — duration is summed from track row strings.
    private var metaLine: String {
        let trackPart = "\(vm.tracks.count) tracks"
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
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
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
                Text(saved ? "Kaydedildi" : "Kaydet")
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
        .help(saved ? "Kitaplığından çıkar" : "Kitaplığına kaydet")
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
                Text("Şarkılar yükleniyor…")
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
                Text("“\(searchText)” için sonuç yok")
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
                                     fallbackThumbnailURL: playlist.thumbnailURL)
                                .opacity(draggedSetVideoId == track.setVideoId ? 0.4 : 1)
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
        let np = media.nowPlaying
        return np.hasTrack && np.title.caseInsensitiveCompare(t.title) == .orderedSame
    }

    @ViewBuilder
    private func trackContextMenu(for t: NativeShellViewModel.TrackSummary) -> some View {
        Button { vm.playTrack(t) } label: { Label("Oynat", systemImage: "play.fill") }
        Button { vm.addToQueue(track: t, playNext: true) } label: {
            Label("Sıradaki olarak çal", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { vm.addToQueue(track: t) } label: { Label("Kuyruğa ekle", systemImage: "text.append") }
        Button { vm.startRadio(t) } label: {
            Label("Radyo başlat", systemImage: "dot.radiowaves.left.and.right")
        }
        Divider()
        Menu {
            Button { vm.beginCreatePlaylist(addingVideoId: t.id) } label: {
                Label("Yeni liste oluştur", systemImage: "plus")
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
        } label: { Label("Çalma listesine ekle", systemImage: "plus") }
        Button { vm.likeTrack(videoId: t.id, title: t.title) } label: {
            Label("Beğenilenlere kaydet", systemImage: "heart")
        }
        Button { vm.dislikeTrack(videoId: t.id, title: t.title) } label: {
            Label("Beğenme", systemImage: "hand.thumbsdown")
        }
        Divider()
        if let aid = t.artistId {
            Button { vm.openArtist(browseId: aid, name: t.artist) } label: {
                Label("Sanatçıya git", systemImage: "music.mic")
            }
        }
        if let alid = t.albumId {
            Button { vm.openAlbum(albumId: alid, title: t.album ?? "", thumbnailURL: t.thumbnailURL) } label: {
                Label("Albüme git", systemImage: "opticaldisc")
            }
        }
        if vm.isEditablePlaylist(playlist) {
            Divider()
            Button(role: .destructive) {
                vm.removeFromPlaylist(tracks: [t], from: playlist)
            } label: { Label("Listeden çıkar", systemImage: "minus.circle") }
        }
        Divider()
        Button { vm.copyLink(videoId: t.id) } label: { Label("Bağlantıyı kopyala", systemImage: "link") }
        Button { vm.openInBrowser(videoId: t.id) } label: { Label("Tarayıcıda aç", systemImage: "safari") }
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
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.4))
                }
            }
            .frame(width: 28, alignment: .trailing)

            // Title column: artwork + title/artist. Flexible so it aligns
            // with the "Başlık" header.
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
                Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : "Not Playing")
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
                .help("Sanatçıya git")
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
                Label("Radyo başlat", systemImage: "dot.radiowaves.left.and.right")
            }
            if !np.artist.isEmpty {
                Button { vm.openArtistByName(np.artist) } label: {
                    Label("Sanatçıya git", systemImage: "music.mic")
                }
            }
            Divider()
            Menu {
                Button { vm.beginCreatePlaylist(addingVideoId: np.videoId) } label: {
                    Label("Yeni liste oluştur", systemImage: "plus")
                }
                if !vm.playlists.isEmpty { Divider() }
                ForEach(vm.playlists) { p in
                    Button(p.title) {
                        vm.addToPlaylist(videoId: np.videoId, playlistId: p.id,
                                         trackTitle: np.title, playlistTitle: p.title)
                    }
                }
            } label: { Label("Çalma listesine ekle", systemImage: "plus") }
            Button { media.run("like") } label: {
                Label(np.liked ? "Beğeniyi kaldır" : "Beğen",
                      systemImage: np.liked ? "heart.fill" : "heart")
            }
            Divider()
            Button { vm.copyLink(videoId: np.videoId) } label: {
                Label("Bağlantıyı kopyala", systemImage: "link")
            }
            Button { vm.openInBrowser(videoId: np.videoId) } label: {
                Label("Tarayıcıda aç", systemImage: "safari")
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
        .help("Beğenilenlere ekle")
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
        .help("Karıştır")
    }

    private var repeatButton: some View {
        let mode = media.nowPlaying.repeatMode
        return Button(action: { media.run("repeat") }) {
            Image(systemName: mode == "ONE" ? "repeat.1" : "repeat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(mode == "NONE" ? .primary.opacity(0.6) : activeTint)
        }
        .buttonStyle(.plain)
        .help("Tekrarla")
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
        .help("Tema")
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
        .help("Sözleri göster")
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
        .help("Kuyruğu aç/kapat (⌘E)")
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
        .help("Şimdi çalıyor (⌘F)")
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
                Text("Sözler")
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
                Text("Sözler yükleniyor…")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = vm.lyrics {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(lyrics.text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(0.92))
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                    if let src = lyrics.source {
                        Text(src)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.45))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                Text("Çalan şarkı yok")
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
                    sectionLabel("Açık")
                    ForEach(Theme.allCases.filter { !$0.isDark }) { row($0) }
                    sectionLabel("Koyu")
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
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.primary.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var header: some View {
        HStack {
            Text("Tema")
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
            .help("Sessize al")
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
        let id = UUID()
        let label: String
        let mode: SleepTimer.Mode
    }

    private let options: [Option] = [
        .init(label: "5 dakika",         mode: .duration(5 * 60)),
        .init(label: "15 dakika",        mode: .duration(15 * 60)),
        .init(label: "30 dakika",        mode: .duration(30 * 60)),
        .init(label: "1 saat",           mode: .duration(60 * 60)),
        .init(label: "Şarkı bitince",     mode: .endOfTrack)
    ]

    private var iconName: String {
        sleep.isActive ? "moon.fill" : "moon"
    }

    private var countdownLabel: String? {
        if let r = sleep.remaining, sleep.isActive {
            let mm = Int(r) / 60
            let ss = Int(r) % 60
            return String(format: "%d:%02d", mm, ss)
        }
        if case .endOfTrack? = sleep.mode { return "EoT" }
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
        .help("Uyku zamanlayıcı")
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("UYKU ZAMANLAYICI")
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
                        Text("İptal")
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
            Text("Kuyruk")
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
                Text("Kuyruk boş")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.45))
                Text("Bir şarkıya sağ tıkla → Kuyruğa ekle.")
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
                                Button("Şimdi çal") { vm.playOwnQueueItem(item) }
                                Button("Kaldır") { vm.removeFromOwnQueue(item) }
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
            Text("SIRADAKİLER")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.primary.opacity(0.5))
            Spacer()
            Button(action: { vm.clearOwnQueue() }) {
                Text("Temizle")
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
        Button("Bu parçaya atla") { vm.jumpToQueueIndex(item.id) }
        if let vid = item.videoId {
            Divider()
            Button("Beğen") { vm.likeTrack(videoId: vid, title: item.title) }
            Button("Beğenme") { vm.dislikeTrack(videoId: vid, title: item.title) }
            Divider()
            Menu("Çalma listesine ekle") {
                if vm.playlists.isEmpty {
                    Text("Listeler yükleniyor…")
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
            Button("Tarayıcıda aç") { vm.openInBrowser(videoId: vid) }
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
                Text(item.artist.isEmpty ? "Manual" : item.artist)
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
