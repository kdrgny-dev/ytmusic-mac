import SwiftUI

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

    // Surface tokens. Distinct enough that each region is visible against
    // its neighbour without being noisy. Tweak in one place.
    private let bgBase    = Color(red: 0.043, green: 0.043, blue: 0.051) // app
    private let bgSurface = Color(red: 0.094, green: 0.094, blue: 0.106) // sidebar / player bar
    private let bgRaised  = Color(red: 0.137, green: 0.137, blue: 0.149) // hover / chips
    private let strokeColor = Color.white.opacity(0.08)

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Sidebar(bg: bgSurface, stroke: strokeColor, vm: vm)
                    Divider().background(strokeColor)
                    MainContent(bg: bgBase, vm: vm)
                    if vm.isQueueVisible {
                        Divider().background(strokeColor)
                        QueuePanel(bg: bgSurface, raised: bgRaised, vm: vm)
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(strokeColor)

                PlayerBar(bg: bgSurface, raised: bgRaised, vm: vm)
                    .frame(height: 96)
            }

            if vm.isSearchVisible {
                SearchOverlay(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            }

            if let msg = vm.toast {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.bottom, 112) // above the player bar
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
            }
        }
        .background(bgBase)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: vm.isQueueVisible)
        .animation(.easeInOut(duration: 0.18), value: vm.isSearchVisible)
        .animation(.easeInOut(duration: 0.2), value: vm.toast)
        .onAppear {
            vm.loadPlaylistsIfNeeded()
            // Land users on Home by default so first impression is content,
            // not the "Pick a playlist" placeholder.
            vm.goHome()
        }
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
                Divider().background(Color.white.opacity(0.08))
                tabBar
                Divider().background(Color.white.opacity(0.08))
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                        .foregroundColor(vm.searchTab == kind ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(vm.searchTab == kind ? Color.white.opacity(0.10) : Color.clear)
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
                .foregroundColor(.white.opacity(0.5))
            TextField("Search songs, artists, albums, playlists…", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .focused($focused)
                .onSubmit {
                    if let first = vm.searchResults.first { vm.openSearchResult(first) }
                }
            if vm.searchLoading {
                ProgressView().controlSize(.small)
            } else if !vm.searchQuery.isEmpty {
                Button(action: { vm.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            Button(action: { vm.toggleSearch() }) {
                Text("⎋")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
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
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(0.25))
                Text("Type to search \(vm.searchTab.label.lowercased())")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.searchError, vm.searchResults.isEmpty, !vm.searchLoading {
            VStack(spacing: 4) {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.searchResults) { r in
                        Button(action: { vm.openSearchResult(r) }) {
                            SearchResultRow(result: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct SearchResultRow: View {
    let result: NativeShellViewModel.SearchResult
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovered ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = result.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    let bg: Color
    let stroke: Color
    @ObservedObject var vm: NativeShellViewModel

    private struct TopItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let action: () -> Void
    }

    private var topItems: [TopItem] {
        [
            .init(id: "home",    icon: "house.fill",            label: "Home",    action: { vm.goHome() }),
            .init(id: "explore", icon: "safari",                label: "Explore", action: { vm.goExplore() }),
            .init(id: "search",  icon: "magnifyingglass",       label: "Search",  action: { vm.toggleSearch() })
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Browse")
                    ForEach(topItems) { item in
                        Button(action: item.action) {
                            sidebarRow(icon: item.icon, label: item.label)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        sectionHeader("Your playlists")
                        Spacer()
                        Button(action: { vm.reload() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                    .padding(.top, 18)

                    playlistSection
                }
                .padding(.vertical, 14)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    @ViewBuilder
    private var playlistSection: some View {
        if vm.loadingPlaylists && vm.playlists.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        } else if let msg = vm.errorMessage, vm.playlists.isEmpty {
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .lineLimit(3)
        } else {
            ForEach(vm.playlists) { p in
                Button(action: { vm.openPlaylist(p) }) {
                    playlistRow(p)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }

    private func sidebarRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundColor(.white.opacity(0.7))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func playlistRow(_ p: NativeShellViewModel.PlaylistSummary) -> some View {
        HStack(spacing: 10) {
            thumbnail(for: p)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(p.title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnail(for p: NativeShellViewModel.PlaylistSummary) -> some View {
        if let urlString = p.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                )
        }
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
            case .playlist(let p):
                PlaylistDetailView(playlist: p, vm: vm)
            case .category:
                CategoryView(vm: vm)
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
                .foregroundColor(.white.opacity(0.35))
            Text("Pick a playlist or open Home")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("Sidebar → Home for recommendations.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
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
                .foregroundColor(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.45))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(enabled ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Category (mood/genre) view

private struct CategoryView: View {
    @ObservedObject var vm: NativeShellViewModel

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

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
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(vm.categoryPlaylists) { p in
                            Button(action: { vm.openPlaylist(p) }) {
                                CategoryPlaylistCard(playlist: p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KATEGORİ")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.55))
            Text(vm.categoryTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            if !vm.categoryPlaylists.isEmpty {
                Text("\(vm.categoryPlaylists.count) playlist")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

private struct CategoryPlaylistCard: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    @State private var hovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(hovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(hovered ? 0.5 : 0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: hovered)
            Text(playlist.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 160, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = playlist.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
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
                    .foregroundColor(.white.opacity(0.55))
                Text("Sana özel öneriler")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("YT Music'in senin için karıştırdığı playlist'ler, sanatçılar ve türler")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button(action: { vm.reloadHome() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
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
        VStack(spacing: 8) {
            ProgressView().controlSize(.large)
            Text("Loading recommendations…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.4))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Button("Retry") { vm.reloadHome() }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.white.opacity(0.1))
                )
        }
        .frame(maxWidth: .infinity, minHeight: 240)
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
                HomeCardView(card: card)
            }
            .buttonStyle(.plain)
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
                        .foregroundColor(.white.opacity(0.5))
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
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
                .foregroundColor(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(enabled ? 0.10 : 0.04))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(enabled ? 0.18 : 0.08), lineWidth: 1)
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

private struct CarouselWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                .foregroundColor(.white)
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
                .stroke(Color.white.opacity(hovered ? 0.3 : 0), lineWidth: 1)
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
    @State private var hovered: Bool = false

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
                    coverShape.stroke(Color.white.opacity(hovered ? 0.18 : 0), lineWidth: 1)
                )
                .scaleEffect(hovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(hovered ? 0.5 : 0.0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: hovered)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(card.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }
}

private struct PlaylistDetailView: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            tracksList
        }
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
                    .foregroundColor(.white.opacity(0.5))
                Text(playlist.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if !vm.tracks.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
            // Save button only makes sense for playlists; albums are
            // saved via like endpoint with different semantics that we
            // haven't wired yet.
            if !isAlbum { saveButton }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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
                Text(saved ? "Saved" : "Save")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(saved ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(saved ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(saved ? "Remove from your library" : "Save to your library")
    }

    @ViewBuilder
    private var cover: some View {
        if let s = playlist.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }

    @ViewBuilder
    private var tracksList: some View {
        if vm.loadingTracks && vm.tracks.isEmpty {
            VStack {
                ProgressView()
                Text("Loading tracks…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.tracksError, vm.tracks.isEmpty {
            Text(msg)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.tracks.enumerated()), id: \.element.id) { idx, track in
                        Button(action: { vm.playTrack(track) }) {
                            TrackRow(index: idx + 1,
                                     track: track,
                                     isPlaying: isCurrentTrack(track),
                                     zebra: idx.isMultiple(of: 2))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { trackContextMenu(for: track) }
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
        Button("Play") { vm.playTrack(t) }
        Button("Play next") { vm.addToQueue(track: t, playNext: true) }
        Button("Add to queue") { vm.addToQueue(track: t) }
        Divider()
        Button("Like") { vm.likeTrack(videoId: t.id, title: t.title) }
        Button("Dislike") { vm.dislikeTrack(videoId: t.id, title: t.title) }
        Divider()
        Menu("Save to playlist") {
            if vm.playlists.isEmpty {
                Text("Loading playlists…")
            } else {
                ForEach(vm.playlists) { p in
                    Button(p.title) {
                        vm.addToPlaylist(videoId: t.id,
                                         playlistId: p.id,
                                         trackTitle: t.title,
                                         playlistTitle: p.title)
                    }
                }
            }
        }
        Divider()
        Button("Open in browser") { vm.openInBrowser(videoId: t.id) }
    }
}

private struct TrackRow: View {
    let index: Int
    let track: NativeShellViewModel.TrackSummary
    let isPlaying: Bool
    let zebra: Bool

    @State private var isHovered: Bool = false

    /// Background tint: hover wins, then isPlaying highlight, then zebra.
    private var rowBackground: Color {
        if isHovered { return Color.white.opacity(0.08) }
        if isPlaying { return Color.accentColor.opacity(0.18) }
        return zebra ? Color.white.opacity(0.03) : .clear
    }

    private var titleColor: Color {
        isPlaying ? Color.accentColor : .white
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
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: 28, alignment: .trailing)

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
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            if let dur = track.duration {
                Text(dur)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = track.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @EnvironmentObject private var media: MediaController
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel

    // Local display state for the progress slider. Updated event-driven
    // from MediaController + a 0.5s tick timer between updates so it
    // doesn't visibly stall waiting for the 4s safety-net poll.
    @State private var displayedTime: Double = 0
    @State private var isDragging: Bool = false

    private let tickTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            progressRow
            controlsRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(bg)
        .onAppear { displayedTime = media.nowPlaying.currentTime }
        .onChange(of: media.nowPlaying.currentTime) { newValue in
            if !isDragging { displayedTime = newValue }
        }
        .onChange(of: media.nowPlaying.title) { _ in
            if !isDragging { displayedTime = media.nowPlaying.currentTime }
        }
        .onReceive(tickTimer) { _ in
            guard !isDragging, media.nowPlaying.isPlaying else { return }
            let total = media.nowPlaying.duration
            displayedTime = min(displayedTime + 0.5, total > 0 ? total : displayedTime + 0.5)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(format(displayedTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 38, alignment: .trailing)
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
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 38, alignment: .leading)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : "Not Playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(media.nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            transport
            queueToggle
        }
    }

    private var queueToggle: some View {
        Button(action: { vm.toggleQueue() }) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(vm.isQueueVisible ? .white : .white.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(vm.isQueueVisible ? Color.white.opacity(0.15) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Toggle Queue (⌘E)")
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
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.35))
                )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var transport: some View {
        HStack(spacing: 14) {
            iconButton("backward.fill") { media.run("prev") }
            iconButton(media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", large: true) {
                media.run("playpause")
            }
            iconButton("forward.fill") { media.run("next") }
        }
    }

    private func iconButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 16 : 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: large ? 38 : 30, height: large ? 38 : 30)
                .background(large ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue panel

private struct QueuePanel: View {
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    private var header: some View {
        HStack {
            Text("Queue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            if !vm.queue.isEmpty {
                Text("\(vm.queue.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            Button(action: { vm.toggleQueue() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
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
                    .foregroundColor(.white.opacity(0.3))
                Text("Queue is empty")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                Text("Right-click a track → Add to queue.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
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
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Play now") { vm.playOwnQueueItem(item) }
                                Button("Remove") { vm.removeFromOwnQueue(item) }
                            }
                        }
                        Divider().background(Color.white.opacity(0.1))
                            .padding(.vertical, 6)
                    }
                    ForEach(vm.queue) { item in
                        Button(action: { vm.jumpToQueueIndex(item.id) }) {
                            QueueRow(item: item, raised: raised)
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
            Text("UP NEXT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(action: { vm.clearOwnQueue() }) {
                Text("Clear")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func queueContextMenu(for item: NativeShellViewModel.QueueItem) -> some View {
        Button("Jump to this track") { vm.jumpToQueueIndex(item.id) }
        if let vid = item.videoId {
            Divider()
            Button("Like") { vm.likeTrack(videoId: vid, title: item.title) }
            Button("Dislike") { vm.dislikeTrack(videoId: vid, title: item.title) }
            Divider()
            Menu("Save to playlist") {
                if vm.playlists.isEmpty {
                    Text("Loading playlists…")
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
            Button("Open in browser") { vm.openInBrowser(videoId: vid) }
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(item.artist.isEmpty ? "Manual" : item.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentColor.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovered ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let s = item.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
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

    var body: some View {
        HStack(spacing: 10) {
            cover
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: item.isPlaying ? .semibold : .regular))
                    .foregroundColor(item.isPlaying ? .green : .white)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(item.isPlaying ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cover: some View {
        if let s = item.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
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
