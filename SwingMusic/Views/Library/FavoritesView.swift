import SwiftUI

enum FavRoute: Hashable { case albums, artists, songs }

struct FavoritesView: View {
    @Environment(AppState.self) var state
    @State private var loading = true
    @State private var startingPlayback = false

    private var isEmpty: Bool { state.favTracks.isEmpty && state.favAlbums.isEmpty && state.favArtists.isEmpty }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if loading && isEmpty {
                ProgressView().tint(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else if isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on a song, album or artist to find it here.")
                )
                .frame(minHeight: 460)
            } else {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    if !state.favRecents.isEmpty { recentsSection }
                    if !state.favTracks.isEmpty { tracksSection }
                    if !state.favAlbums.isEmpty { albumsSection }
                    if !state.favArtists.isEmpty { artistsSection }
                    Color.clear.frame(height: 100)
                }
            }
        }
        .squeezeMiniPlayer(state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground() }
        .detailScrollTitle("Favorites", after: 40)
        .navigationDestination(for: FavRoute.self) { route in
            switch route {
            case .albums: FavoriteAlbumsGridView()
            case .artists: FavoriteArtistsGridView()
            case .songs: FavoriteTracksView()
            }
        }
        .task {
            await state.loadFavorites()
            loading = false
        }
    }

    // MARK: Header

    // Drawn in the page rather than as the navigation title, so it shares the sections' left edge.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorites")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DetailLayout.inset)

            if !state.favTracks.isEmpty {
                // pads itself by the same inset
                DetailPlayButtons(
                    play: { playAll(shuffled: false) },
                    shuffle: { playAll(shuffled: true) }
                )
                .disabled(startingPlayback)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: String {
        var parts = ["\(state.favTracksTotal) \(state.favTracksTotal == 1 ? "song" : "songs")"]
        if state.favAlbumsTotal > 0 { parts.append("\(state.favAlbumsTotal) \(state.favAlbumsTotal == 1 ? "album" : "albums")") }
        if state.favArtistsTotal > 0 { parts.append("\(state.favArtistsTotal) \(state.favArtistsTotal == 1 ? "artist" : "artists")") }
        return parts.joined(separator: " · ")
    }

    // Plays every favorite, not just the preview: fetched in one request, the loaded ones offline.
    private func playAll(shuffled: Bool) {
        startingPlayback = true
        Task {
            let all = (try? await API.shared.allFavoriteTracks()) ?? state.favTracks
            state.player.playAll(all, shuffled: shuffled, source: .favorite)
            startingPlayback = false
        }
    }

    // MARK: Sections

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Songs", route: state.favTracksTotal > state.favPreviewTracks ? .songs : nil)
            VStack(spacing: 0) {
                ForEach(state.favTracks.prefix(state.favPreviewTracks)) { t in
                    TrackRow(track: t, active: state.isCurrentTrack(t)) {
                        state.playFavorite(t)
                    }
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently Favorited", route: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(state.favRecents) { item in
                        switch item {
                        case .album(let a):
                            NavigationLink(value: a) { AlbumCard(album: a, size: 150, kind: .album) }.buttonStyle(.plain)
                        case .artist(let a):
                            NavigationLink(value: a) { ArtistCard(artist: a, size: 150, kind: .artist) }.buttonStyle(.plain)
                        case .track(let t):
                            Button { state.playFavorite(t) } label: { TrackCard(track: t, kind: .track) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, DetailLayout.inset, for: .scrollContent)
            .scrollClipDisabled()
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Albums", route: .albums)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(state.favAlbums.prefix(state.favPreviewCards)) { a in
                        NavigationLink(value: a) { AlbumCard(album: a, size: 150) }.buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, DetailLayout.inset, for: .scrollContent)
            .scrollClipDisabled()
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Artists", route: .artists)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(state.favArtists.prefix(state.favPreviewCards)) { a in
                        NavigationLink(value: a) { ArtistCard(artist: a, size: 110) }.buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, DetailLayout.inset, for: .scrollContent)
            .scrollClipDisabled()
        }
    }

    // Apple Music style: the title itself opens the full list when there is more to see.
    @ViewBuilder
    private func sectionHeader(_ title: String, route: FavRoute?) -> some View {
        let label = HStack(spacing: 4) {
            Text(title).font(.title2.bold()).foregroundStyle(.primary)
            if route != nil {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        Group {
            if let route {
                NavigationLink(value: route) { label }.buttonStyle(.plain)
            } else {
                label
            }
        }
        .padding(.horizontal, DetailLayout.inset)
    }
}

// The Favorites tab: its own navigation stack, with the same detail screens and zoom transitions as Library.
struct FavoritesTabView: View {
    @Environment(AppState.self) var state
    @Namespace private var zoomNS

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.favoritesPath) {
            FavoritesView()
                .appDestinations(zoom: zoomNS)
        }
        .environment(\.zoomNamespace, zoomNS)
    }
}
