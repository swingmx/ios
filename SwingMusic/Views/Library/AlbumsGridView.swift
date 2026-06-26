import SwiftUI

enum AlbumSort: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case title = "Title"
    case artist = "Artist"
    case releaseDate = "Release Date"
    var id: String { rawValue }

    func apply(_ albums: [Album]) -> [Album] {
        switch self {
        case .recentlyAdded: albums
        case .title: albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: albums.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .releaseDate: albums.sorted { ($0.date ?? 0) > ($1.date ?? 0) }
        }
    }
}

struct AlbumsGridView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("albumsSort") private var sortRaw = AlbumSort.recentlyAdded.rawValue
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var sort: AlbumSort { AlbumSort(rawValue: sortRaw) ?? .recentlyAdded }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(sort.apply(state.allAlbums)) { a in
                    NavigationLink(value: a) { AlbumCard(album: a, size: 150) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Albums")
        .toolbar { sortMenu }
        .task { await state.loadAlbums() }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(AlbumSort.allCases) { s in
                        Text(s.rawValue).tag(s.rawValue)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Sort albums")
        }
    }
}

enum ArtistSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case mostTracks = "Most Tracks"
    case mostAlbums = "Most Albums"
    var id: String { rawValue }

    func apply(_ artists: [Artist]) -> [Artist] {
        switch self {
        case .name: artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostTracks: artists.sorted { ($0.trackcount ?? 0) > ($1.trackcount ?? 0) }
        case .mostAlbums: artists.sorted { ($0.albumcount ?? 0) > ($1.albumcount ?? 0) }
        }
    }
}

struct ArtistsGridView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("artistsSort") private var sortRaw = ArtistSort.name.rawValue
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    private var sort: ArtistSort { ArtistSort(rawValue: sortRaw) ?? .name }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(sort.apply(state.allArtists)) { a in
                    NavigationLink(value: a) { ArtistCard(artist: a, size: 110) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Artists")
        .toolbar { sortMenu }
        .task { await state.loadArtists() }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(ArtistSort.allCases) { s in
                        Text(s.rawValue).tag(s.rawValue)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Sort artists")
        }
    }
}

struct FavoriteTracksView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.favTracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                        state.player.play(t, from: state.favTracks, source: .favorite)
                    }

                    .onAppear {
                        if i >= state.favTracks.count - 5 {
                            Task { await state.loadMoreFavoriteTracks() }
                        }
                    }
                }
                if state.favTracks.count < state.favTracksTotal {
                    ProgressView().tint(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
            .padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Songs")
        .task { if state.favTracks.isEmpty { await state.loadFavorites() } }
    }
}

struct FavoriteAlbumsGridView: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(Array(state.favAlbums.enumerated()), id: \.element.id) { i, a in
                    NavigationLink(value: a) { AlbumCard(album: a, size: 150) }
                        .buttonStyle(.plain)
                        .onAppear {
                            if i >= state.favAlbums.count - 4 {
                                Task { await state.loadMoreFavoriteAlbums() }
                            }
                        }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
            if state.favAlbums.count < state.favAlbumsTotal {
                ProgressView().tint(.secondary).padding(.vertical, 20)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Favorite Albums")
        .task { if state.favAlbums.isEmpty { await state.loadFavorites() } }
    }
}

struct FavoriteArtistsGridView: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(Array(state.favArtists.enumerated()), id: \.element.id) { i, a in
                    NavigationLink(value: a) { ArtistCard(artist: a, size: 110) }
                        .buttonStyle(.plain)
                        .onAppear {
                            if i >= state.favArtists.count - 4 {
                                Task { await state.loadMoreFavoriteArtists() }
                            }
                        }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
            if state.favArtists.count < state.favArtistsTotal {
                ProgressView().tint(.secondary).padding(.vertical, 20)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Favorite Artists")
        .task { if state.favArtists.isEmpty { await state.loadFavorites() } }
    }
}

struct RecentlyAddedView: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(state.recentAdded) { a in
                    NavigationLink(value: a) { AlbumCard(album: a, size: 150) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Recently Added")
            }
}
