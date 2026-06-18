import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var state: AppState
    @State private var loading = true

    private var breakdown: String {
        var parts: [String] = []
        if !state.favTracks.isEmpty { parts.append("\(state.favTracks.count) Tracks") }
        if !state.favAlbums.isEmpty { parts.append("\(state.favAlbums.count) Albums") }
        if !state.favArtists.isEmpty { parts.append("\(state.favArtists.count) Artists") }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if loading && state.favTracks.isEmpty && state.favAlbums.isEmpty && state.favArtists.isEmpty {
                VStack { Spacer(); ProgressView().tint(.white); Spacer() }
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
        .background { AmbientBackground() }
        .navigationTitle("Favorites")
        .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
        .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
        .task {
            await state.loadFavorites()
            loading = false
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Songs", count: state.favTracks.count)
            VStack(spacing: 0) {
                ForEach(state.favTracks) { t in
                    TrackRow(track: t, active: state.player.current == t) {
                        state.player.play(t, from: state.favTracks, source: .favorite)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Albums", count: state.favAlbums.count)
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
            sectionHeader("Artists", count: state.favArtists.count)
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

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
            Text("\(count)").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
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
