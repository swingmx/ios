import SwiftUI

private struct GenreInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let artists: [String]

    init(_ name: String, _ icon: String, _ color: Color, _ artists: [String] = []) {
        self.id = name
        self.name = name
        self.icon = icon
        self.color = color
        self.artists = artists
    }
}

private let localGenres: [GenreInfo] = [
    GenreInfo("Pop", "star.fill", .pink, ["Taylor Swift", "Dua Lipa", "The Weeknd"]),
    GenreInfo("Rock", "guitars.fill", .red, ["Queen", "Nirvana", "AC/DC"]),
    GenreInfo("Hip-Hop", "mic.fill", .orange, ["Kendrick Lamar", "Drake", "Eminem"]),
    GenreInfo("R&B", "heart.fill", .purple, ["Frank Ocean", "SZA", "The Weeknd"]),
    GenreInfo("Electronic", "waveform", .cyan, ["Daft Punk", "Deadmau5", "Calvin Harris"]),
    GenreInfo("Jazz", "music.quarternote.3", .yellow, ["Miles Davis", "John Coltrane"]),
    GenreInfo("Classical", "pianokeys", .brown, ["Mozart", "Beethoven", "Bach"]),
    GenreInfo("Country", "leaf.fill", .green, ["Johnny Cash", "Dolly Parton"]),
    GenreInfo("Metal", "bolt.fill", .gray, ["Metallica", "Slipknot", "Iron Maiden"]),
    GenreInfo("Indie", "sparkles", .teal, ["Arctic Monkeys", "Tame Impala", "Radiohead"]),
    GenreInfo("Latin", "sun.max.fill", .orange, ["Bad Bunny", "J Balvin", "Shakira"]),
    GenreInfo("Reggae", "tropicalstorm", .green, ["Bob Marley"]),
    GenreInfo("Blues", "drop.fill", .blue, ["B.B. King", "Muddy Waters"]),
    GenreInfo("Soul", "flame.fill", .indigo, ["Marvin Gaye", "Aretha Franklin"]),
    GenreInfo("Folk", "tree.fill", .mint, ["Bob Dylan", "Bon Iver"]),
    GenreInfo("Punk", "exclamationmark.triangle.fill", .red, ["Green Day", "Ramones"]),
    GenreInfo("Ambient", "cloud.fill", .cyan, ["Brian Eno"]),
    GenreInfo("Funk", "speaker.wave.3.fill", .purple, ["James Brown", "Parliament"]),
]

struct SearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var result: SearchResult?
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @State private var genreImages: [String: String] = GenreImageCache.load()
    @State private var recents: [RecentSearchItem] = SearchHistory.load()

    var body: some View {
        NavigationStack(path: $state.searchPath) {
            VStack(spacing: 0) {
                if query.isEmpty && result == nil {
                    idleView
                } else if searching {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else if let r = result {
                    ScrollView(.vertical, showsIndicators: false) {
                        results(r).padding(.top, 8).padding(.bottom, 100)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .background { AmbientBackground() }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, Albums, Artists")
            .onChange(of: query) { _, v in
                task?.cancel()
                if v.isEmpty { result = nil; return }
                task = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await doSearch(v)
                }
            }
            .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
            .onChange(of: state.searchPath) { _, _ in

                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private var idleView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if recents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Search your library")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Find songs, albums and artists.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent Searches")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        Button("Clear") { SearchHistory.clear(); recents = [] }
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    ForEach(recents) { item in
                        recentRow(item)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private func recentRow(_ item: RecentSearchItem) -> some View {
        let isArtist = item.kind == .artist
        let label = HStack(spacing: 12) {
            Img(url: isArtist ? API.shared.artistImg(item.image, size: "medium")
                              : API.shared.img(item.image, size: "medium"),
                radius: isArtist ? 22 : 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: item.kind == .track ? "play.circle.fill" : "chevron.right")
                .font(.system(size: item.kind == .track ? 22 : 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        switch item.kind {
        case .track:
            Button {
                if let t = item.track {
                    state.player.play(t, from: [t], source: .search(item.title))
                }
            } label: { label }
            .buttonStyle(.plain)
        case .album:
            NavigationLink(value: Album(stub: item.hash, title: item.title, image: item.image, date: nil, albumartists: nil)) { label }
                .buttonStyle(.plain)
        case .artist:
            NavigationLink(value: Artist(stub: item.hash, name: item.title, image: item.image)) { label }
                .buttonStyle(.plain)
        }
    }

    private var genreGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Browse")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(localGenres) { genre in
                        Button { query = genre.name } label: {
                            ZStack(alignment: .bottomLeading) {
                                genre.color

                                if let imgPath = genreImages[genre.name] {
                                    Img(url: API.shared.artistImg(imgPath, size: "medium"), radius: 0)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }

                                Text(genre.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                    .padding(12)
                            }
                            .frame(height: 100)

                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Color.clear.frame(height: 100)
            }
            .padding(.top, 8)
        }
    }

    private func loadGenreImages() async {
        let missing = localGenres.filter { genreImages[$0.name] == nil }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (String, String?).self) { group in
            for genre in missing {
                group.addTask {
                    for artistName in genre.artists {
                        if let result = try? await API.shared.search(artistName),
                           let artist = result.artists?.first,
                           !artist.image.isEmpty {
                            return (genre.name, artist.image)
                        }
                    }
                    return (genre.name, nil)
                }
            }
            for await (name, image) in group {
                if let image {
                    genreImages[name] = image
                }
            }
        }
        GenreImageCache.save(genreImages)
    }

    private func results(_ r: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if let top = r.top_result, !top.displayName.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Result").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).padding(.horizontal, 16)
                    topResultCard(top)
                        .padding(.horizontal, 16)
                }
            }
            if let tracks = r.tracks, !tracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Songs").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).padding(.horizontal, 16)
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.prefix(8).enumerated()), id: \.element.id) { _, t in
                            TrackRow(track: t, active: state.player.current == t) {
                                record(RecentSearchItem(kind: .track, hash: t.trackhash, title: t.title, subtitle: t.artist, image: t.image, track: t))
                                state.player.play(t, from: tracks, source: .search(query))
                            }
                        }
                    }
                    .nativeCard(18)
                    .padding(.horizontal, 16)
                }
            }
            if let albums = r.albums, !albums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Albums").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(albums.prefix(10)) { a in
                                NavigationLink(value: a) { AlbumCard(album: a, size: 140) }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        record(RecentSearchItem(kind: .album, hash: a.albumhash, title: a.title, subtitle: a.artist, image: a.image, track: nil))
                                    })
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }
            if let artists = r.artists, !artists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Artists").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(artists.prefix(8)) { a in
                                NavigationLink(value: a) { ArtistCard(artist: a, size: 100) }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        record(RecentSearchItem(kind: .artist, hash: a.artisthash, title: a.name, subtitle: "Artist", image: a.image, track: nil))
                                    })
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topResultCard(_ top: TopResult) -> some View {
        let isArtist = top.type == "artist"
        let card = HStack(spacing: 14) {
            Img(url: isArtist ? API.shared.artistImg(top.image ?? "", size: "medium")
                              : API.shared.img(top.image ?? "", size: "medium"),
                radius: isArtist ? 30 : 10)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(top.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(top.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .nativeCard(18)

        switch top.type {
        case "artist":
            NavigationLink(value: Artist(stub: top.artisthash ?? "", name: top.displayName, image: top.image ?? "")) { card }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    record(RecentSearchItem(kind: .artist, hash: top.artisthash ?? "", title: top.displayName, subtitle: "Artist", image: top.image ?? "", track: nil))
                })
        case "album":
            NavigationLink(value: Album(stub: top.albumhash ?? "", title: top.displayName, image: top.image ?? "", date: nil, albumartists: nil)) { card }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    record(RecentSearchItem(kind: .album, hash: top.albumhash ?? "", title: top.displayName, subtitle: "Album", image: top.image ?? "", track: nil))
                })
        default:
            card
        }
    }

    private func doSearch(_ q: String) async {
        searching = true
        result = try? await API.shared.search(q)
        searching = false
    }

    private func record(_ item: RecentSearchItem) {
        SearchHistory.add(item)
        recents = SearchHistory.load()
    }
}

enum GenreImageCache {
    private static let key = "genreImages.v1"

    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func save(_ dict: [String: String]) {
        UserDefaults.standard.set(dict, forKey: key)
    }
}

struct RecentSearchItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case track, album, artist }
    let kind: Kind
    let hash: String
    let title: String
    let subtitle: String
    let image: String
    let track: Track?

    var id: String { kind.rawValue + ":" + hash }
    static func == (l: RecentSearchItem, r: RecentSearchItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum SearchHistory {
    private static let key = "searchHistory.items.v1"
    private static let maxItems = 20

    static func load() -> [RecentSearchItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentSearchItem].self, from: data) else { return [] }
        return items
    }

    static func add(_ item: RecentSearchItem) {
        var items = load()
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
