import SwiftUI

enum FavRoute: Hashable { case albums, artists, songs }

struct FavoritesView: View {
    @EnvironmentObject var state: AppState
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
                    if !state.favTracks.isEmpty { header }
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
        .detailScrollTitle("Favorite Songs", after: 330)
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

    // MARK: Header, laid out like an album's

    private var header: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let minY = geo.frame(in: .scrollView).minY
                FavoritesCollage(tracks: state.favTracks, size: coverSize)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                    .scaleEffect(minY > 0 ? 1 + minY / 600 : 1 + minY / 2400, anchor: .bottom)
                    .offset(y: minY > 0 ? -minY * 0.3 : -minY * 0.2)
                    .opacity(minY < 0 ? max(0.25, 1 + minY / 500) : 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: coverSize)
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Favorite Songs")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            DetailPlayButtons(
                play: { playAll(shuffled: false) },
                shuffle: { playAll(shuffled: true) }
            )
            .disabled(startingPlayback)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var coverSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 320 : 270
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
                    TrackRow(track: t, active: state.player.current == t) {
                        state.playFavorite(t)
                    }
                }
            }
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
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
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
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
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
        .padding(.horizontal, 16)
    }
}

// The favorites' cover: the artwork of the first four songs (one per album), like a playlist's.
// With fewer than four different covers, the newest one fills it.
struct FavoritesCollage: View {
    let tracks: [Track]
    var size: CGFloat

    private var images: [String] {
        var seen = Set<String>()
        return tracks.map(\.image).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        let imgs = images
        Group {
            if imgs.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { tile(imgs[0]); tile(imgs[1]) }
                    GridRow { tile(imgs[2]); tile(imgs[3]) }
                }
            } else if let first = imgs.first {
                tile(first, full: true)
            } else {
                Color.white.opacity(0.05)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func tile(_ image: String, full: Bool = false) -> some View {
        let side = full ? size : size / 2
        let sizes = full || side > 200 ? ["original", "", "medium"] : ["", "medium"]
        return Img(urls: sizes.compactMap { API.shared.img(image, size: $0) }, radius: 0)
            .frame(width: side, height: side)
            .clipped()
    }
}

// The Favorites tab: its own navigation stack, with the same detail screens and zoom transitions as Library.
struct FavoritesTabView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $state.favoritesPath) {
            FavoritesView()
                .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash).navigationTransition(.zoom(sourceID: "album-\($0.albumhash)", in: zoomNS)) }
                .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash).navigationTransition(.zoom(sourceID: "artist-\($0.artisthash)", in: zoomNS)) }
                .navigationDestination(for: Playlist.self) { PlaylistDetailView(id: $0.id, name: $0.name) }
                .navigationDestination(for: Folder.self) { FolderBrowserView(path: $0.path, title: $0.name) }
                .navigationDestination(for: Mix.self) { MixDetailView(mix: $0) }
        }
        .environment(\.zoomNamespace, zoomNS)
    }
}
