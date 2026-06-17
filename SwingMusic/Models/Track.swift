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

    var artist: String { artists?.first?.name ?? "Unknown Artist" }
    var artisthash: String { artisthashes?.first ?? artists?.first?.artisthash ?? "" }

    var id: String { trackhash }
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.trackhash == rhs.trackhash }
    func hash(into hasher: inout Hasher) { hasher.combine(trackhash) }
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
    var id: String { artisthash }
    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.artisthash == rhs.artisthash }
    func hash(into hasher: inout Hasher) { hasher.combine(artisthash) }
}

extension Artist {

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
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String?
    let images: [PlaylistImage]?
    let trackcount: Int
    let duration: Int
    let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, image, images, trackcount, duration, pinned, count
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
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AlbumDetail: Codable {
    let info: Album
    let tracks: [Track]
}

struct ArtistStat: Decodable, Hashable {
    let cssclass: String
    let value: String
    let text: String
    let image: String?
}

struct ArtistDetail: Decodable {
    let artist: Artist
    let tracks: [Track]
    let stats: [ArtistStat]?

    enum CodingKeys: String, CodingKey { case artist, tracks, stats }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decode(Artist.self, forKey: .artist)
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        stats = try? c.decode([ArtistStat].self, forKey: .stats)
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

struct ArtistsResponse: Codable {
    let items: [Artist]
    let total: Int
}

struct SearchResult: Codable {
    let tracks: [Track]?
    let albums: [Album]?
    let artists: [Artist]?
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

struct FolderResponse: Decodable {
    let folders: [Folder]
    let tracks: [Track]
    let path: String?
}

struct Mix: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let sourcehash: String
    let trackcount: Int?
    let extra: Extra

    struct Extra: Decodable, Hashable {
        let type: String?
        let og_sourcehash: String?
        let image: MixImageRef?
        let images: [MixImageRef]?
    }
    struct MixImageRef: Decodable, Hashable {
        let image: String?
        let color: String?
    }

    var imageFile: String? { extra.image?.image ?? extra.images?.first?.image }

    var ogSourcehash: String { extra.og_sourcehash ?? sourcehash }

    enum CodingKeys: String, CodingKey { case id, title, sourcehash, trackcount, extra }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        title = (try? c.decode(String.self, forKey: .title)) ?? "Mix"
        sourcehash = (try? c.decode(String.self, forKey: .sourcehash)) ?? ""
        trackcount = try? c.decode(Int.self, forKey: .trackcount)
        extra = (try? c.decode(Extra.self, forKey: .extra)) ?? Extra(type: nil, og_sourcehash: nil, image: nil, images: nil)
    }

    static func == (lhs: Mix, rhs: Mix) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum HomeItem: Identifiable, Hashable {
    case album(Album)
    case artist(Artist)
    case track(Track)
    case playlist(Playlist)
    case mix(Mix)

    var id: String {
        switch self {
        case .album(let a): "al:\(a.albumhash)"
        case .artist(let a): "ar:\(a.artisthash)"
        case .track(let t): "tr:\(t.trackhash)"
        case .playlist(let p): "pl:\(p.id)"
        case .mix(let m): "mix:\(m.id)"
        }
    }
}

struct HomeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [HomeItem]
}
