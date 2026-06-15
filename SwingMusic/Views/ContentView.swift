import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView(expanded: $state.showPlayer)
        }
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
            guard let target, !state.showPlayer else { return }
            navigateToTarget(target)
        }
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
