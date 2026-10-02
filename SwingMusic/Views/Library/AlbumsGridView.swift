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
            FavoritesListHeader(
                title: "Favorite Songs",
                tagline: FavoritesListHeader.tagline(count: state.favTracksTotal, singular: "song", plural: "songs"),
                leading: 16)
            LazyVStack(spacing: 0) {
                ForEach(Array(state.favTracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: max(state.favTracksTotal, state.favTracks.count) - i,
                             active: state.player.current == t) {
                        state.playFavorite(t)
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
        .detailScrollTitle("Favorite Songs", after: 70)
        .task { if state.favTracks.isEmpty { await state.loadFavorites() } }
    }
}

struct FavoriteAlbumsGridView: View {
    @EnvironmentObject var state: AppState
    @State private var width: CGFloat = 0
    private let cols = [GridItem(.adaptive(minimum: FavoritesListHeader.albumCard), spacing: FavoritesListHeader.gridSpacing)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            FavoritesListHeader(
                title: "Favorite Albums",
                tagline: FavoritesListHeader.tagline(count: state.favAlbumsTotal, singular: "album", plural: "albums"),
                leading: FavoritesListHeader.firstAlbumInset(width: width))
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .detailScrollTitle("Favorite Albums", after: 70)
        .task { if state.favAlbums.isEmpty { await state.loadFavorites() } }
    }
}

struct FavoriteArtistsGridView: View {
    @EnvironmentObject var state: AppState
    @State private var width: CGFloat = 0
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            FavoritesListHeader(
                title: "Favorite Artists",
                tagline: FavoritesListHeader.tagline(count: state.favArtistsTotal, singular: "artist", plural: "artists"),
                leading: FavoritesListHeader.firstAlbumInset(width: width))
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .detailScrollTitle("Favorite Artists", after: 70)
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

struct FavoritesListHeader: View {
    let title: String
    let tagline: String
    let leading: CGFloat

    static let margin: CGFloat = 16
    static let albumCard: CGFloat = 150
    static let gridSpacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            Text(tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leading)
        .padding(.trailing, Self.margin)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    static func tagline(count: Int, singular: String, plural: String) -> String {
        "You have \(count) favorited \(count == 1 ? singular : plural)"
    }

    static func firstAlbumInset(width: CGFloat) -> CGFloat {
        let available = width - margin * 2
        guard available >= albumCard else { return margin }
        let columns = max(1, ((available + gridSpacing) / (albumCard + gridSpacing)).rounded(.down))
        let columnWidth = (available - gridSpacing * (columns - 1)) / columns
        return margin + (columnWidth - albumCard) / 2
    }
}
