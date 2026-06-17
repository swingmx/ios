import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var state: AppState
    @State private var showingCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var showSettings = false

    private let menu: [LibItem] = [.folders, .artists, .albums, .favorites, .downloads]

    var body: some View {
        NavigationStack {

            List {
                Section {
                    ForEach(menu) { item in
                        NavigationLink(value: item) {
                            HStack {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.tintColor)
                                    .frame(width: 28)
                                Text(item.rawValue)
                            }
                        }
                    }
                }

                if !state.allPlaylists.isEmpty {
                    Section {
                        ForEach(state.allPlaylists) { pl in
                            NavigationLink(value: pl) {
                                HStack(spacing: 12) {
                                    PlaylistImageGrid(playlist: pl, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name)
                                            .lineLimit(1)
                                        Text("\(pl.trackcount) songs")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            Button {
                                showingCreateAlert = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                }

                if !state.recentAdded.isEmpty {
                    Section(header: Text("Recently Added")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(state.recentAdded) { a in
                                    NavigationLink(value: a) { AlbumCard(album: a, size: 130) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("New Playlist", isPresented: $showingCreateAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
                Button("Create") {
                    let name = newPlaylistName
                    newPlaylistName = ""
                    Task {
                        _ = try? await API.shared.createPlaylist(name)
                        await state.loadPlaylists()
                    }
                }
            } message: {
                Text("Enter a name for your new playlist.")
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(for: LibItem.self) { item in
                switch item {
                case .folders: FolderBrowserView()
                case .favorites: FavoritesView()
                case .favoriteArtists: ArtistsGridView()
                case .artists: ArtistsGridView()
                case .favoriteAlbums: AlbumsGridView()
                case .albums: AlbumsGridView()
                case .newestAlbums: RecentlyAddedView()
                case .recentlyPlayed: AlbumsGridView()
                case .songs: FavoriteTracksView()
                case .favoriteSongs: FavoriteTracksView()
                case .downloads: DownloadsView()
                }
            }
            .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(id: $0.id, name: $0.name) }
        }
        .task {
            await state.loadAlbums()
            await state.loadArtists()
            await state.loadPlaylists()

            if state.recentAdded.isEmpty { await state.loadHome() }
        }
    }
}

struct PlaylistsListView: View {
    @EnvironmentObject var state: AppState
    @State private var showingCreateAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(state.allPlaylists) { pl in
                    NavigationLink(value: pl) {
                        HStack(spacing: 14) {
                            PlaylistImageGrid(playlist: pl, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pl.name).font(.system(size: 16)).foregroundStyle(.primary)
                                Text("\(pl.trackcount) songs").font(.system(size: 13)).foregroundStyle(.white.opacity(0.3))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.15))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 100)
        }
        .background { AmbientBackground() }
        .navigationTitle("Playlists")
                .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateAlert = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                }
            }
        }
        .alert("New Playlist", isPresented: $showingCreateAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") {
                let name = newPlaylistName
                newPlaylistName = ""
                Task {
                    _ = try? await API.shared.createPlaylist(name)
                    await state.loadPlaylists()
                }
            }
        } message: {
            Text("Enter a name for your new playlist.")
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(id: $0.id, name: $0.name) }
        .task { await state.loadPlaylists() }
    }
}

enum LibItem: String, CaseIterable, Identifiable, Hashable {
    case folders = "Folders"
    case favorites = "Favorites"
    case favoriteArtists = "Favorite Artists"
    case artists = "Artists"
    case favoriteAlbums = "Favorite Albums"
    case albums = "Albums"
    case newestAlbums = "Newest Albums"
    case recentlyPlayed = "Recently Played"
    case songs = "Songs"
    case favoriteSongs = "Favorite Songs"
    case downloads = "Downloads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .folders: "folder.fill"
        case .favorites: "heart.fill"
        case .favoriteArtists: "heart.fill"
        case .artists: "music.mic"
        case .favoriteAlbums: "heart.fill"
        case .albums: "square.stack"
        case .newestAlbums: "sparkles"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .songs: "music.note"
        case .favoriteSongs: "heart.fill"
        case .downloads: "arrow.down.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .folders: .blue
        case .favorites, .favoriteArtists, .favoriteAlbums, .favoriteSongs: .pink
        case .artists: .blue
        case .albums: .blue
        case .newestAlbums: .orange
        case .recentlyPlayed: .green
        case .songs: .blue
        case .downloads: .green
        }
    }
}
