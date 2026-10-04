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
    @Environment(AppState.self) var state
    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var result: SearchResult?
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @State private var recents: [RecentSearchItem] = SearchHistory.load()

    enum SearchScope: String, CaseIterable, Identifiable {
        case all = "All", songs = "Songs", albums = "Albums", artists = "Artists"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.searchPath) {
            content
                .navigationTitle("Search")
                .searchable(text: $query, prompt: "Songs, Albums, Artists")
                .searchScopes($scope, activation: .onSearchPresentation) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .onSubmit(of: .search) { runSearch(query, delay: 0) }
                .onChange(of: query) { _, v in runSearch(v, delay: 300_000_000) }
                .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
                .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            recentsList
        } else if let r = result {
            if isEmpty(r) {
                ContentUnavailableView.search(text: query)
            } else {
                resultsList(r)
            }
        } else if searching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var recentsList: some View {
        if recents.isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Find songs, albums and artists.")
            )
        } else {
            List {
                Section {
                    ForEach(recents) { item in recentRow(item) }
                        .onDelete { offsets in
                            recents.remove(atOffsets: offsets)
                            SearchHistory.save(recents)
                        }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") { SearchHistory.clear(); recents = [] }
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .squeezeMiniPlayer(state)
        }
    }

    @ViewBuilder
    private func recentRow(_ item: RecentSearchItem) -> some View {
        switch item.kind {
        case .track:
            Button {
                if let t = item.track { state.player.play(t, from: [t], source: .search(item.title)) }
            } label: {
                row(image: API.shared.img(item.image, size: "small"), round: false,
                    title: item.title, subtitle: "Song · " + item.subtitle)
            }
            .tint(.primary)
        case .album:
            NavigationLink(value: Album(stub: item.hash, title: item.title, image: item.image, date: nil, albumartists: nil)) {
                row(image: API.shared.img(item.image, size: "small"), round: false,
                    title: item.title, subtitle: "Album · " + item.subtitle)
            }
        case .artist:
            NavigationLink(value: Artist(stub: item.hash, name: item.title, image: item.image)) {
                row(image: API.shared.artistImg(item.image, size: "small"), round: true,
                    title: item.title, subtitle: "Artist")
            }
        }
    }

    private func isEmpty(_ r: SearchResult) -> Bool {
        (r.tracks ?? []).isEmpty && (r.albums ?? []).isEmpty && (r.artists ?? []).isEmpty
    }

    private func resultsList(_ r: SearchResult) -> some View {
        let tracks = r.tracks ?? []
        let albums = r.albums ?? []
        let artists = r.artists ?? []
        let limit = scope == .all ? 5 : .max
        return List {
            if scope == .all, let top = r.top_result, !top.displayName.isEmpty {
                Section("Top Result") { topResultRow(top, tracks: tracks) }
            }
            if scope == .all || scope == .songs, !tracks.isEmpty {
                Section("Songs") {
                    ForEach(tracks.prefix(limit)) { t in
                        Button {
                            record(RecentSearchItem(kind: .track, hash: t.trackhash, title: t.title, subtitle: t.artist, image: t.image, track: t))
                            state.player.play(t, from: tracks, source: .search(query))
                        } label: {
                            row(image: API.shared.img(t.image, size: "small"), round: false,
                                title: t.title, subtitle: t.artist,
                                playing: state.isCurrentTrack(t), explicit: t.isExplicit)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing) {
                            Button { state.player.addNext(t) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                                .tint(.indigo)
                            Button { state.player.addLast(t) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
                                .tint(.orange)
                        }
                    }
                }
            }
            if scope == .all || scope == .albums, !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums.prefix(limit)) { a in
                        Button {
                            record(RecentSearchItem(kind: .album, hash: a.albumhash, title: a.title, subtitle: a.artist, image: a.image, track: nil))
                            state.searchPath.append(a)
                        } label: {
                            HStack {
                                row(image: API.shared.img(a.image, size: "small"), round: false,
                                    title: a.title, subtitle: "Album · " + a.artist)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            if scope == .all || scope == .artists, !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists.prefix(limit)) { a in
                        Button {
                            record(RecentSearchItem(kind: .artist, hash: a.artisthash, title: a.name, subtitle: "Artist", image: a.image, track: nil))
                            state.searchPath.append(a)
                        } label: {
                            HStack {
                                row(image: API.shared.artistImg(a.image, size: "small"), round: true,
                                    title: a.name, subtitle: "Artist")
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .squeezeMiniPlayer(state)
    }

    @ViewBuilder
    private func topResultRow(_ top: TopResult, tracks: [Track]) -> some View {
        switch top.type {
        case "artist":
            NavigationLink(value: Artist(stub: top.artisthash ?? "", name: top.displayName, image: top.image ?? "")) {
                row(image: API.shared.artistImg(top.image ?? "", size: "medium"), round: true,
                    title: top.displayName, subtitle: "Artist", size: 64)
            }
        case "album":
            NavigationLink(value: Album(stub: top.albumhash ?? "", title: top.displayName, image: top.image ?? "", date: nil, albumartists: nil)) {
                row(image: API.shared.img(top.image ?? "", size: "medium"), round: false,
                    title: top.displayName, subtitle: "Album", size: 64)
            }
        default:
            Button {
                guard let t = tracks.first(where: { $0.trackhash == top.trackhash }) ?? tracks.first else { return }
                record(RecentSearchItem(kind: .track, hash: t.trackhash, title: t.title, subtitle: t.artist, image: t.image, track: t))
                state.player.play(t, from: tracks, source: .search(query))
            } label: {
                row(image: API.shared.img(top.image ?? "", size: "medium"), round: false,
                    title: top.displayName, subtitle: "Song", size: 64)
            }
            .tint(.primary)
        }
    }

    private func row(image: URL?, round: Bool, title: String, subtitle: String,
                     playing: Bool = false, explicit: Bool = false, size: CGFloat = 48) -> some View {
        HStack(spacing: 12) {
            Img(url: image, radius: round ? size / 2 : 6)
                .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(playing ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .explicitBadge(explicit)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(.rect)
    }

    private func runSearch(_ q: String, delay: UInt64) {
        task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { result = nil; searching = false; return }
        task = Task {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            searching = true
            let r = try? await API.shared.search(trimmed)
            guard !Task.isCancelled else { return }
            result = r
            searching = false
        }
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

    static func save(_ items: [RecentSearchItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
