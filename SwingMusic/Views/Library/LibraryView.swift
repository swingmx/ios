import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) var state
    @State private var showingCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var showSettings = false
    @Namespace private var zoomNS

    private let menu: [LibItem] = [.folders, .artists, .albums, .playlists, .savedMixes, .downloads]

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.libraryPath) {
            List {
                Section {
                    Button {
                        Task { await state.shuffleLibrary() }
                    } label: {
                        HStack {
                            Image(systemName: "shuffle")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            Text("Shuffle Library")
                                .foregroundStyle(.primary)
                            Spacer()
                            if state.shufflingLibrary { ProgressView() }
                        }
                    }
                    .disabled(state.shufflingLibrary)
                }

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
                    let pinned = state.allPlaylists.filter { $0.pinned }
                    let others = state.allPlaylists.filter { !$0.pinned }

                    Section {
                        ForEach(pinned.isEmpty ? others : pinned) { playlistRow($0) }
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

                    if !pinned.isEmpty && !others.isEmpty {
                        Section {
                            ForEach(others) { playlistRow($0) }
                        }
                    }
                }

                if !state.recentAdded.isEmpty {
                    Section(header: Text("Recently Added")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(Array(state.recentAdded.enumerated()), id: \.offset) { _, a in
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
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            .scrollContentBackground(.hidden)
            .squeezeMiniPlayer(state)
            .background { AmbientBackground() }
            .refreshable {
                await state.loadAlbums()
                await state.loadArtists()
                await state.loadPlaylists()
                await state.loadHome()
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        UserAvatar(size: 22, photoSize: 44)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .sharedBackgroundVisibility(state.hasUserImage ? .hidden : .automatic)
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
                case .favoriteArtists: ArtistsGridView()
                case .artists: ArtistsGridView()
                case .favoriteAlbums: AlbumsGridView()
                case .albums: AlbumsGridView()
                case .playlists: PlaylistsListView()
                case .savedMixes: SavedMixesView()
                case .newestAlbums: RecentlyAddedView()
                case .recentlyPlayed: AlbumsGridView()
                case .songs: FavoriteTracksView()
                case .favoriteSongs: FavoriteTracksView()
                case .downloads: DownloadsView()
                }
            }
            .appDestinations(zoom: zoomNS)
        }
        .environment(\.zoomNamespace, zoomNS)
        .task {
            await state.loadAlbums()
            await state.loadArtists()
            await state.loadPlaylists()
            if state.recentAdded.isEmpty { await state.loadHome() }
        }
    }

    @ViewBuilder
    private func playlistRow(_ pl: Playlist) -> some View {
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
                Spacer(minLength: 0)
                if pl.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(45))
                }
            }
        }
    }
}

struct SavedMixesView: View {
    @Environment(AppState.self) var state
    @State private var mixes: [Mix]?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if let mixes, mixes.isEmpty {
                    ContentUnavailableView("No Saved Mixes", systemImage: "bookmark",
                                           description: Text("Mixes you save show up here."))
                        .padding(.top, 80)
                } else if mixes == nil {
                    ProgressView().tint(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                }
                ForEach(mixes ?? []) { mix in
                    NavigationLink(value: mix) {
                        HStack(spacing: 14) {
                            MixArtwork(mix: mix, cornerRadius: 6)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mix.title).font(.system(size: 16)).foregroundStyle(.primary).lineLimit(1)
                                Text(mix.typeLabel).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle("Saved Mixes")
        .task { mixes = (try? await API.shared.savedMixes()) ?? mixes ?? [] }
    }
}

struct PlaylistsListView: View {
    @Environment(AppState.self) var state
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
                                Text("\(pl.trackcount) songs").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
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
        .task { await state.loadPlaylists() }
    }
}

enum LibItem: String, CaseIterable, Identifiable, Hashable {
    case folders = "Folders"
    case favoriteArtists = "Favorite Artists"
    case artists = "Artists"
    case favoriteAlbums = "Favorite Albums"
    case albums = "Albums"
    case playlists = "Playlists"
    case savedMixes = "Saved Mixes"
    case newestAlbums = "Newest Albums"
    case recentlyPlayed = "Recently Played"
    case songs = "Songs"
    case favoriteSongs = "Favorite Songs"
    case downloads = "Downloads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .folders: "folder.fill"
        case .favoriteArtists: "heart.fill"
        case .artists: "music.mic"
        case .favoriteAlbums: "heart.fill"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        case .savedMixes: "bookmark.fill"
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
        case .favoriteArtists, .favoriteAlbums, .favoriteSongs: .pink
        case .artists: .blue
        case .albums: .blue
        case .playlists: .purple
        case .savedMixes: .indigo
        case .newestAlbums: .orange
        case .recentlyPlayed: .green
        case .songs: .blue
        case .downloads: .green
        }
    }
}
