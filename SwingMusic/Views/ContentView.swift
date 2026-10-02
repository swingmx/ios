import SwiftUI
import LNPopupUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    private let player = AudioPlayer.shared
    @State private var currentTrack: Track?
    @State private var isPlaying = false
    @State private var barProgress: Float = 0
    @Namespace private var playerTransitionNamespace
    private let playerTransitionID = "now-playing"
    @State private var barPresented = false
    @State private var barImage: Image?
    #if DEBUG
    @State private var debugShowsEqualizer = false
    @State private var debugShowsWidgets = false
    #endif
    @Environment(\.popupBarPlacement) private var popupBarPlacement

    private func loadBarImage(_ t: Track?) async {
        guard let t, let url = API.shared.img(t.image, size: "small") else { barImage = nil; return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        if let (data, _) = try? await Net.session.data(for: req), let ui = UIImage(data: data) {
            barImage = Image(uiImage: ui)
        }
    }

    var body: some View {
        tabView
            .popup(isBarPresented: $barPresented, isPopupOpen: $state.showPlayer) {
                NowPlayingView()
                    .environmentObject(state)
                    .environment(PlayerStore.shared)
                    .environment(AppSettings.shared)
                    .environment(LyricsStore.shared)
                    .environment(\.colorScheme, .dark)
                    .popupTitle(verbatim: currentTrack?.title ?? "", subtitle: currentTrack?.allArtists)
                    .popupImage(barImage)
                    .popupProgress(barProgress)
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
            }
            .popupCloseButtonStyle(.none)
            .popupInteractionStyle(.drag)
            .onReceive(player.$current) { track in
                currentTrack = track
                barPresented = (track != nil)
                Task { await loadBarImage(track) }
            }
            .onReceive(player.$playing) { isPlaying = $0 }
            .onReceive(
                player.$time
                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            ) { t in
                let total = player.total
                barProgress = total > 0 ? Float(min(max(t / total, 0), 1)) : 0
            }
            .onChange(of: state.lyrics?.lines.count) { _, _ in
                LyricsStore.shared.update(from: state.lyrics)
            }
            .onChange(of: state.showPlayer) { _, open in
                if open { LyricsStore.shared.update(from: state.lyrics) }
            }
            .sheet(item: $state.requestedTrackForPlaylist) { track in
                AddToPlaylistSheet(track: track)
                    .environmentObject(state)
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
        TabView(selection: $state.tab) {
            Tab("Listening Now", systemImage: "house.fill", value: AppState.Tab.home) {
                HomeView()
                    .blocksTouchesBehindBottomBars()
            }
            Tab("Library", systemImage: "music.note.list", value: AppState.Tab.library) {
                LibraryView()
                    .blocksTouchesBehindBottomBars()
            }
            Tab("Favorites", systemImage: "heart.fill", value: AppState.Tab.favorites) {
                FavoritesTabView()
                    .blocksTouchesBehindBottomBars()
            }
            Tab(value: AppState.Tab.search, role: .search) {
                SearchView()
                    .blocksTouchesBehindBottomBars()
            }
        }
        .tint(.blue)
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
    func blocksTouchesBehindBottomBars() -> some View {
        modifier(BottomBarsTouchBlocker())
    }
}
