import SwiftUI

enum FavRoute: Hashable { case albums, artists, songs }

struct FavoritesView: View {
    @EnvironmentObject var state: AppState
    @State private var loading = true

    private var breakdown: String {
        var parts: [String] = []
        if state.favTracksTotal > 0 { parts.append("\(state.favTracksTotal) Tracks") }
        if state.favAlbumsTotal > 0 { parts.append("\(state.favAlbumsTotal) Albums") }
        if state.favArtistsTotal > 0 { parts.append("\(state.favArtistsTotal) Artists") }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if loading && state.favTracks.isEmpty && state.favAlbums.isEmpty && state.favArtists.isEmpty {
                VStack { Spacer(); ProgressView().tint(.secondary); Spacer() }
                    .frame(minHeight: 400)
            } else if state.favTracks.isEmpty && state.favAlbums.isEmpty && state.favArtists.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 40) {
                    if !breakdown.isEmpty {
                        Text(breakdown)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    if !state.favArtists.isEmpty { artistsSection }
                    if !state.favAlbums.isEmpty { albumsSection }
                    if !state.favTracks.isEmpty { tracksSection }
                    Color.clear.frame(height: 100)
                }
                .padding(.top, 8)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Favorites")
        .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
        .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
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

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Songs", count: state.favTracksTotal, seeAll: state.favTracksTotal > state.favTracks.count ? .songs : nil)
            VStack(spacing: 0) {
                ForEach(state.favTracks.prefix(8)) { t in
                    TrackRow(track: t, active: state.player.current == t) {
                        state.player.play(t, from: state.favTracks, source: .favorite)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Albums", count: state.favAlbumsTotal, seeAll: .albums)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(state.favAlbums) { a in
                        NavigationLink(value: a) { AlbumCard(album: a, size: 140) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Artists", count: state.favArtistsTotal, seeAll: .artists)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(state.favArtists) { a in
                        NavigationLink(value: a) { ArtistCard(artist: a, size: 100) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int, seeAll: FavRoute? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
            Text("\(count)").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let seeAll {
                NavigationLink(value: seeAll) {
                    Text("See All").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No favorites yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Tap the heart on a song, album or artist to find it here.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
