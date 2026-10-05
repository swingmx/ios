import SwiftUI
import LNPopupUI

struct ContentView: View {
    @Environment(AppState.self) var state
    private let player = AudioPlayer.shared
    @State private var barPresented = false
    #if DEBUG
    @State private var debugShowsEqualizer = false
    @State private var debugShowsWidgets = false
    #endif

    // Anything this body reads re-renders every screen in the app, popup content included: LNPopupUI
    // resets the root view of both on each update, which rebuilds any menu that is open. Playback state
    // that changes while music plays belongs in MiniPlayerItem instead.
    var body: some View {
        @Bindable var state = state
        tabView
            .popup(isBarPresented: $barPresented, isPopupOpen: $state.showPlayer) {
                MiniPlayerItem {
                    NowPlayingView()
                        .environment(state)
                        .environment(PlayerStore.shared)
                        .environment(AppSettings.shared)
                        .environment(LyricsStore.shared)
                        .environment(\.colorScheme, .dark)
                }
            }
            .popupCloseButtonStyle(.none)
            .popupBarCustomizer { $0.tintColor = .label }
            .popupInteractionStyle(.drag)
            .onReceive(player.$current.map { $0 != nil }.removeDuplicates()) { barPresented = $0 }
            .onChange(of: state.lyricsRevision) { _, _ in
                LyricsStore.shared.update(from: state.lyrics)
            }
            .onChange(of: state.showPlayer) { _, open in
                if open { LyricsStore.shared.update(from: state.lyrics) }
            }
            .sheet(item: $state.requestedTrackForPlaylist) { track in
                AddToPlaylistSheet(track: track)
                    .environment(state)
            }
            .onChange(of: state.tab) { _, _ in state.scroll.reset() }
            #if DEBUG
            .sheet(isPresented: $debugShowsEqualizer) { EqualizerSheet() }
            .sheet(isPresented: $debugShowsWidgets) { WidgetDebugPreview() }
            .onReceive(NotificationCenter.default.publisher(for: .init("debugShowWidgets"))) { _ in debugShowsWidgets = true }
            .onReceive(NotificationCenter.default.publisher(for: .init("debugShowEqualizer"))) { _ in debugShowsEqualizer = true }
            #endif
            .onChange(of: state.navigationTarget) { _, target in
                guard target != nil else { return }
                if state.showPlayer { state.showPlayer = false } else { navigateToTarget(target!) }
            }
            .onChange(of: state.showPlayer) { _, open in
                if !open, let target = state.navigationTarget { navigateToTarget(target) }
            }
    }

    private var tabView: some View {
        @Bindable var state = state
        return TabView(selection: $state.tab) {
            Tab("Listening Now", systemImage: "house.fill", value: AppState.Tab.home) {
                HomeView()
                    .neutralTint()
                    .blocksTouchesBehindBottomBars()
            }
            Tab("Library", systemImage: "music.note.list", value: AppState.Tab.library) {
                LibraryView()
                    .neutralTint()
                    .blocksTouchesBehindBottomBars()
            }
            Tab("Favorites", systemImage: "heart.fill", value: AppState.Tab.favorites) {
                FavoritesTabView()
                    .neutralTint()
                    .blocksTouchesBehindBottomBars()
            }
            Tab(value: AppState.Tab.search, role: .search) {
                SearchView()
                    .neutralTint()
                    .blocksTouchesBehindBottomBars()
            }
        }
        // The tab bar's selected tab shows the accent; each tab's content is neutral (neutralTint).
        .tint(Color.appAccent)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func navigateToTarget(_ target: AppState.NavTarget) {
        state.navigationTarget = nil
        switch state.tab {
        case .home:
            switch target {
            case .album(let a): state.homePath.append(a)
            case .artist(let a): state.homePath.append(a)
            case .folder(let f): state.homePath.append(f)
            }
        case .library:
            switch target {
            case .album(let a): state.libraryPath.append(a)
            case .artist(let a): state.libraryPath.append(a)
            case .folder(let f): state.libraryPath.append(f)
            }
        case .favorites:
            switch target {
            case .album(let a): state.favoritesPath.append(a)
            case .artist(let a): state.favoritesPath.append(a)
            case .folder(let f): state.favoritesPath.append(f)
            }
        default:
            state.tab = .home
            switch target {
            case .album(let a): state.homePath.append(a)
            case .artist(let a): state.homePath.append(a)
            case .folder(let f): state.homePath.append(f)
            }
        }
    }
}

// The mini player's title, artwork and buttons. They change on every track and play/pause, so they
// live here rather than in ContentView, where each change would re-render the whole app.
private struct MiniPlayerItem<Content: View>: View {
    @ViewBuilder let content: Content
    private let player = AudioPlayer.shared
    @State private var currentTrack: Track?
    @State private var isPlaying = false
    @State private var barImage: Image?
    @Environment(\.popupBarPlacement) private var popupBarPlacement

    var body: some View {
        content
            .popupTitle(verbatim: currentTrack?.title ?? "", subtitle: currentTrack?.allArtists)
            .popupImage(barImage)
            .popupBarItems {
                ToolbarItemGroup(placement: .popupBar) {
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                    if popupBarPlacement != .inline {
                        Button {
                            player.next()
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                }
            }
            .onReceive(player.$current) { track in
                currentTrack = track
                Task { await loadBarImage(track) }
            }
            .onReceive(player.$playing) { isPlaying = $0 }
    }

    private func loadBarImage(_ t: Track?) async {
        guard let t, let url = API.shared.img(t.image, size: "small") else { barImage = nil; return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        if let (data, _) = try? await Net.session.data(for: req), let ui = UIImage(data: data) {
            barImage = Image(uiImage: ui)
        }
    }
}

// On iOS 26 the tab bar and the mini player float with gaps around them, and the mini player's bar
// lets touches outside its glass pass through (LNPopupController's _LNTouchPassthroughView), so a tap
// in a gap would reach the content scrolled underneath. This catches those taps. It sits under the
// bars, so taps on the bars themselves still reach them.
private struct BottomBarsTouchBlocker: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let barsHeight = geo.safeAreaInsets.bottom
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: barsHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: barsHeight)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    // Controls inside a tab default to black or white; only what should stand out uses Color.appAccent.
    func neutralTint() -> some View { tint(.primary) }

    func blocksTouchesBehindBottomBars() -> some View {
        modifier(BottomBarsTouchBlocker())
    }
}
