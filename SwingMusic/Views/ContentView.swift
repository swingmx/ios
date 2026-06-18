import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    @State private var hasTrack = AudioPlayer.shared.current != nil

    var body: some View {
        nativeTabView
        .fullScreenCover(isPresented: $state.showPlayer, onDismiss: onPlayerDismissed) {
            FullPlayerView(show: $state.showPlayer)
                .environmentObject(state)
                .presentationBackground(.clear)
        }
        .sheet(item: $state.requestedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(state)
        }
        .onChange(of: state.tab) { _, _ in
            state.scrollOffset = 0
        }
        .onChange(of: state.navigationTarget) { _, target in
            guard target != nil else { return }
            if state.showPlayer {
                state.showPlayer = false
            } else {
                navigateToTarget(target!)
            }
        }
        .onReceive(AudioPlayer.shared.$current) { hasTrack = $0 != nil }
    }

    @ViewBuilder
    private var nativeTabView: some View {
        if #available(iOS 26.0, *) {
            if hasTrack {
                tabView
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        NowPlayingAccessory(expanded: $state.showPlayer)
                    }
            } else {
                tabView
            }
        } else {
            tabView
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MiniPlayerView(expanded: $state.showPlayer)
                }
        }
    }

    private var tabView: some View {
        TabView(selection: $state.tab) {
            Tab("Listening Now", systemImage: "house.fill", value: AppState.Tab.home) {
                HomeView()
            }
            Tab("Library", systemImage: "music.note.list", value: AppState.Tab.library) {
                LibraryView()
            }
            Tab(value: AppState.Tab.search, role: .search) {
                SearchView()
            }
        }
        .tint(.blue)
    }

    private func onPlayerDismissed() {
        if let target = state.navigationTarget {
            navigateToTarget(target)
        }
    }

    private func navigateToTarget(_ target: AppState.NavTarget) {
        state.navigationTarget = nil
        switch state.tab {
        case .home:
            switch target {
            case .album(let a): state.homePath.append(a)
            case .artist(let a): state.homePath.append(a)
            }
        case .library:
            switch target {
            case .album(let a): state.libraryPath.append(a)
            case .artist(let a): state.libraryPath.append(a)
            }
        default:
            state.tab = .home
            switch target {
            case .album(let a): state.homePath.append(a)
            case .artist(let a): state.homePath.append(a)
            }
        }
    }
}
