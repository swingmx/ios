import Foundation

struct Track: Codable, Identifiable, Equatable, Hashable {
    let trackhash: String
    let title: String
    let album: String
    let albumhash: String
    let duration: Int
    let filepath: String
    let image: String
    let trackno: Int?
    let disc: Int?
    let date: Int?
    let bitrate: Int?
    let genres: [Genre]?
    let artists: [TrackArtist]?
    let albumartists: [TrackArtist]?
    let artisthashes: [String]?
    let color: String?
    let blurhash: String?
    let explicit: Bool?
    // As of when the track was fetched; AppState.isTrackFavorite also accounts for later changes.
    let isFavorite: Bool?

    var isExplicit: Bool { explicit == true }
    var artist: String { artists?.first?.name ?? "Unknown Artist" }
    var artisthash: String { artisthashes?.first ?? artists?.first?.artisthash ?? "" }
    var allArtists: String {
        let names = (artists ?? []).map { $0.name }
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    var id: String { trackhash }
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.trackhash == rhs.trackhash }
    func hash(into hasher: inout Hasher) { hasher.combine(trackhash) }

    enum CodingKeys: String, CodingKey {
        case trackhash, title, album, albumhash, duration, filepath, image
        case trackno = "track"
        case disc, date, bitrate, genres, artists, albumartists, artisthashes, color, blurhash, explicit
        case isFavorite = "is_favorite"
        case extra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackhash = (try? c.decode(String.self, forKey: .trackhash)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        album = (try? c.decode(String.self, forKey: .album)) ?? ""
        albumhash = (try? c.decode(String.self, forKey: .albumhash)) ?? ""
        duration = (try? c.decode(Int.self, forKey: .duration)) ?? 0
        filepath = (try? c.decode(String.self, forKey: .filepath)) ?? ""
        image = (try? c.decode(String.self, forKey: .image)) ?? ""
        trackno = try? c.decode(Int.self, forKey: .trackno)
        disc = try? c.decode(Int.self, forKey: .disc)
        date = try? c.decode(Int.self, forKey: .date)
        bitrate = try? c.decode(Int.self, forKey: .bitrate)
        genres = try? c.decode([Genre].self, forKey: .genres)
        artists = try? c.decode([TrackArtist].self, forKey: .artists)
        albumartists = try? c.decode([TrackArtist].self, forKey: .albumartists)
        artisthashes = try? c.decode([String].self, forKey: .artisthashes)
        color = try? c.decode(String.self, forKey: .color)
        blurhash = try? c.decode(String.self, forKey: .blurhash)
        var ex: Bool?
        if let b = try? c.decode(Bool.self, forKey: .explicit) { ex = b }
        else if let i = try? c.decode(Int.self, forKey: .explicit) { ex = i != 0 }
        else if let s = try? c.decode(String.self, forKey: .explicit) {
            ex = ["1", "true", "yes", "explicit"].contains(s.lowercased())
        }
        if ex != true, let extra = try? c.decode(ExtraTags.self, forKey: .extra), extra.isExplicit {
            ex = true
        }
        explicit = ex
        isFavorite = try? c.decode(Bool.self, forKey: .isFavorite)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trackhash, forKey: .trackhash)
        try c.encode(title, forKey: .title)
        try c.encode(album, forKey: .album)
        try c.encode(albumhash, forKey: .albumhash)
        try c.encode(duration, forKey: .duration)
        try c.encode(filepath, forKey: .filepath)
        try c.encode(image, forKey: .image)
        try c.encodeIfPresent(trackno, forKey: .trackno)
        try c.encodeIfPresent(disc, forKey: .disc)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encodeIfPresent(genres, forKey: .genres)
        try c.encodeIfPresent(artists, forKey: .artists)
        try c.encodeIfPresent(albumartists, forKey: .albumartists)
        try c.encodeIfPresent(artisthashes, forKey: .artisthashes)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(blurhash, forKey: .blurhash)
        try c.encodeIfPresent(explicit, forKey: .explicit)
        try c.encodeIfPresent(isFavorite, forKey: .isFavorite)
    }
}

private struct ExtraTags: Decodable {
    let isExplicit: Bool

    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func value(_ k: Key) -> String? {
            if let a = try? c.decode([String].self, forKey: k) { return a.first }
            if let s = try? c.decode(String.self, forKey: k) { return s }
            if let i = try? c.decode(Int.self, forKey: k) { return String(i) }
            if let b = try? c.decode(Bool.self, forKey: k) { return b ? "1" : "0" }
            return nil
        }
        var explicit = false
        for k in c.allKeys {
            let name = k.stringValue.lowercased()
            guard let v = value(k)?.trimmingCharacters(in: .whitespaces).lowercased() else { continue }
            switch name {
            case "itunesadvisory", "advisory", "rtng", "contentrating":
                if v == "1" || v == "4" || v == "explicit" { explicit = true }
            case "explicit", "explicit_lyrics", "parental_advisory":
                if ["1", "true", "yes", "explicit"].contains(v) { explicit = true }
            default:
                break
            }
        }
        isExplicit = explicit
    }
}

struct Genre: Codable, Hashable {
    let name: String
    let genrehash: String
}

struct TrackArtist: Codable, Hashable {
    let name: String
    let artisthash: String
}

struct Album: Codable, Identifiable, Hashable {
    let albumhash: String
    let title: String
    let image: String
    let date: Int?
    let duration: Int?
    let trackcount: Int?
    let albumartists: [TrackArtist]?
    let color: String?
    let blurhash: String?
    let copyright: String?
    // Sent with an album's own page; absent on cards.
    var isFavorite: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case albumhash, title, image, date, duration, trackcount, albumartists, color, blurhash, copyright
        case isFavorite = "is_favorite"
    }

    var artist: String { albumartists?.first?.name ?? "Unknown Artist" }
    var artisthash: String { albumartists?.first?.artisthash ?? "" }

    var id: String { albumhash }
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.albumhash == rhs.albumhash }
    func hash(into hasher: inout Hasher) { hasher.combine(albumhash) }
}

struct Artist: Codable, Identifiable, Hashable {
    let artisthash: String
    let name: String
    let image: String
    let trackcount: Int?
    let albumcount: Int?
    let duration: Int?
    let genres: [Genre]?
    let color: String?
    // Sent with an artist's own page; absent on cards.
    var isFavorite: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case artisthash, name, image, trackcount, albumcount, duration, genres, color
        case isFavorite = "is_favorite"
    }

    var id: String { artisthash }
    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.artisthash == rhs.artisthash }
    func hash(into hasher: inout Hasher) { hasher.combine(artisthash) }
}

extension Artist {
    // The server names an artist's image after the artist. Stubs built from a track use this rather
    // than the track's album art, which the artist screen would otherwise show as the portrait.
    static func imageFile(for hash: String) -> String { "\(hash).webp" }

    init(stub hash: String, name: String) {
        self.init(stub: hash, name: name, image: Artist.imageFile(for: hash))
    }

    init(stub hash: String, name: String, image: String) {
        self.init(artisthash: hash, name: name, image: image,
                  trackcount: nil, albumcount: nil, duration: nil, genres: nil, color: nil)
    }
}

extension Album {
    init(stub hash: String, title: String, image: String, date: Int?, albumartists: [TrackArtist]?) {
        self.init(albumhash: hash, title: title, image: image, date: date,
                  duration: nil, trackcount: nil, albumartists: albumartists,
                  color: nil, blurhash: nil, copyright: nil)
    }
}

struct PlaylistImage: Codable, Hashable {
    let image: String?

    private enum CodingKeys: String, CodingKey { case image }

    // /playlists sends {"image": "<hash>.webp", "color": …}; the home feed sends just "<hash>.webp".
    init(from decoder: Decoder) throws {
        if let hash = try? decoder.singleValueContainer().decode(String.self) {
            image = hash
        } else {
            image = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .image)
        }
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String?
    let images: [PlaylistImage]?
    let trackcount: Int
    let duration: Int
    let pinned: Bool
    let hasImage: Bool?

    // The uploaded cover's file name. The server sends "None" when there is none, and
    // has_image false when the file is missing, in which case it would answer with an SVG fallback.
    var customImage: String? {
        guard let image, !image.isEmpty, image != "None", hasImage != false else { return nil }
        return image
    }

    enum CodingKeys: String, CodingKey {
        case id, name, image, images, trackcount, duration, pinned, count
        case hasImage = "has_image"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intID)
        } else {
            self.id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        image = try? container.decode(String.self, forKey: .image)
        images = try? container.decode([PlaylistImage].self, forKey: .images)
        trackcount = (try? container.decode(Int.self, forKey: .trackcount)) ?? (try? container.decode(Int.self, forKey: .count)) ?? 0
        duration = (try? container.decode(Int.self, forKey: .duration)) ?? 0
        pinned = (try? container.decode(Bool.self, forKey: .pinned)) ?? false
        hasImage = try? container.decode(Bool.self, forKey: .hasImage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(image, forKey: .image)
        try container.encode(images, forKey: .images)
        try container.encode(trackcount, forKey: .trackcount)
        try container.encode(duration, forKey: .duration)
        try container.encode(pinned, forKey: .pinned)
        try container.encodeIfPresent(hasImage, forKey: .hasImage)
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AlbumDetail: Codable {
    let info: Album
    let tracks: [Track]
    // Same shape as the artist's, minus the top album and plus how complete the album is.
    var stats: [ArtistStat]? = nil
}

struct ArtistStat: Codable, Hashable {
    let cssclass: String
    let value: String
    let text: String
    let image: String?
}

struct ArtistDetail: Decodable {
    let artist: Artist
    let tracks: [Track]
    let stats: [ArtistStat]?
    let albumSections: [ArtistAlbumSection]

    enum CodingKeys: String, CodingKey { case artist, tracks, stats, albums }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decode(Artist.self, forKey: .artist)
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        stats = try? c.decode([ArtistStat].self, forKey: .stats)
        albumSections = (try? c.decode(ArtistAlbumGroups.self, forKey: .albums))?.sections ?? []
    }
}

private struct ArtistAlbumGroups: Decodable {
    let albums: [Album]?
    let singles_and_eps: [Album]?
    let appearances: [Album]?
    let compilations: [Album]?

    var sections: [ArtistAlbumSection] {
        [("Albums", albums), ("Singles & EPs", singles_and_eps), ("Appearances", appearances), ("Compilations", compilations)]
            .compactMap { title, list in
                guard let list, !list.isEmpty else { return nil }
                return ArtistAlbumSection(title: title, albums: list)
            }
    }
}

struct PlaylistDetail: Codable {
    let info: Playlist
    let tracks: [Track]
}

struct AlbumsResponse: Codable {
    let items: [Album]
    let total: Int
}

struct FavoritesSummary: Decodable {
    struct Count: Decodable {
        let tracks: Int
        let albums: Int
        let artists: Int
    }
    let count: Count
}

struct FavoriteTracksPage: Decodable {
    let tracks: [Track]
    let total: Int
    enum CodingKeys: String, CodingKey { case tracks, total }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? tracks.count
    }
}

struct FavoriteAlbumsPage: Decodable {
    let albums: [Album]
    let total: Int
    enum CodingKeys: String, CodingKey { case albums, total }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albums = (try? c.decode([Album].self, forKey: .albums)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? albums.count
    }
}

struct FavoriteArtistsPage: Decodable {
    let artists: [Artist]
    let total: Int
    enum CodingKeys: String, CodingKey { case artists, total }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artists = (try? c.decode([Artist].self, forKey: .artists)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? artists.count
    }
}

struct ArtistsResponse: Codable {
    let items: [Artist]
    let total: Int
}

struct SearchResult: Codable {
    let tracks: [Track]?
    let albums: [Album]?
    let artists: [Artist]?
    let top_result: TopResult?
}

struct TopResult: Codable, Hashable {
    let type: String
    let artisthash: String?
    let albumhash: String?
    let trackhash: String?
    let name: String?
    let title: String?
    let image: String?
    let color: String?

    var displayName: String { name ?? title ?? "" }
    var subtitle: String { type.capitalized }
}

struct AuthResponse: Codable {
    let accesstoken: String?
    let msg: String?
}

struct ColorResponse: Codable {
    let color: String?
}

struct FavoriteCheckResponse: Codable {
    let is_favorite: Bool
}

struct ArtistAlbumSection: Decodable, Hashable {
    let title: String
    let albums: [Album]
}

struct Folder: Decodable, Identifiable, Hashable {
    let name: String
    let path: String
    let trackcount: Int?
    let foldercount: Int?

    enum CodingKeys: String, CodingKey {
        case name, path, foldercount
        case trackcount, count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        trackcount = (try? c.decode(Int.self, forKey: .trackcount)) ?? (try? c.decode(Int.self, forKey: .count))
        foldercount = try? c.decode(Int.self, forKey: .foldercount)
    }

    var id: String { path }
    static func == (lhs: Folder, rhs: Folder) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

extension Folder {
    init(path: String, name: String, trackcount: Int? = nil, foldercount: Int? = nil) {
        self.path = path
        self.name = name
        self.trackcount = trackcount
        self.foldercount = foldercount
    }
}

extension Playlist {
    init(stub id: String, name: String, image: String?) {
        self.id = id
        self.name = name
        self.image = image
        self.images = nil
        self.trackcount = 0
        self.duration = 0
        self.pinned = false
        self.hasImage = nil
    }
}

extension Mix {
    init(stub id: String, title: String, image: String) {
        self.id = id
        self.title = title
        self.sourcehash = ""
        self.trackcount = nil
        self.extra = Extra(type: nil, og_sourcehash: nil,
                           image: MixImageRef(image: image, color: nil), images: nil)
        self.tagline = nil
        self.time = nil
    }
}

struct FolderResponse: Decodable {
    let folders: [Folder]
    let tracks: [Track]
    let path: String?
}

struct Mix: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let sourcehash: String
    let trackcount: Int?
    let extra: Extra
    let tagline: String?
    let time: String?

    struct Extra: Codable, Hashable {
        let type: String?
        let og_sourcehash: String?
        let image: MixImageRef?
        let images: [MixImageRef]?
    }
    struct MixImageRef: Codable, Hashable {
        let image: String?
        let color: String?
        // "artist" images come from the artist image endpoint, anything else from track thumbnails.
        var type: String? = nil
    }

    var imageFile: String? { extra.image?.image ?? extra.images?.first?.image }
    var ogSourcehash: String { extra.og_sourcehash ?? sourcehash }

    enum CodingKeys: String, CodingKey {
        case id, title, sourcehash, trackcount, extra, time
        case tagline = "description"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        title = (try? c.decode(String.self, forKey: .title)) ?? "Mix"
        sourcehash = (try? c.decode(String.self, forKey: .sourcehash)) ?? ""
        trackcount = try? c.decode(Int.self, forKey: .trackcount)
        extra = (try? c.decode(Extra.self, forKey: .extra)) ?? Extra(type: nil, og_sourcehash: nil, image: nil, images: nil)
        tagline = try? c.decode(String.self, forKey: .tagline)
        time = try? c.decode(String.self, forKey: .time)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(sourcehash, forKey: .sourcehash)
        try c.encodeIfPresent(trackcount, forKey: .trackcount)
        try c.encode(extra, forKey: .extra)
        try c.encodeIfPresent(tagline, forKey: .tagline)
        try c.encodeIfPresent(time, forKey: .time)
    }

    static func == (lhs: Mix, rhs: Mix) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Your favorite songs as one item, as Recently Played shows them after playing from favorites.
struct FavoritesItem: Codable, Hashable {
    // The last favorited track's artwork.
    let image: String?
    let count: Int?
}

enum HomeItem: Identifiable, Hashable {
    case album(Album)
    case artist(Artist)
    case track(Track)
    case playlist(Playlist)
    case mix(Mix)
    case favorites(FavoritesItem)

    var id: String {
        switch self {
        case .album(let a): "al:\(a.albumhash)"
        case .artist(let a): "ar:\(a.artisthash)"
        case .track(let t): "tr:\(t.trackhash)"
        case .playlist(let p): "pl:\(p.id)"
        case .mix(let m): "mix:\(m.id)"
        case .favorites: "favorites"
        }
    }

    // One item of a home section, from its "type" and "item" JSON; nil for kinds the app doesn't show.
    static func decode(type: String, json: Data) -> HomeItem? {
        let d = JSONDecoder()
        switch type {
        case "album": return (try? d.decode(Album.self, from: json)).map(HomeItem.album)
        case "artist": return (try? d.decode(Artist.self, from: json)).map(HomeItem.artist)
        case "track": return (try? d.decode(Track.self, from: json)).map(HomeItem.track)
        case "playlist": return (try? d.decode(Playlist.self, from: json)).map(HomeItem.playlist)
        case "mix": return (try? d.decode(Mix.self, from: json)).map(HomeItem.mix)
        case "favorite": return (try? d.decode(FavoritesItem.self, from: json)).map(HomeItem.favorites)
        default: return nil
        }
    }
}

struct HomeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let items: [HomeItem]
}
