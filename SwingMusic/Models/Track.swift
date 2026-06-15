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
    var id: String { artisthash }
    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.artisthash == rhs.artisthash }
    func hash(into hasher: inout Hasher) { hasher.combine(artisthash) }
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

struct ArtistDetail: Codable {
    let artist: Artist
    let tracks: [Track]
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
    let is_fav: Bool
}

struct ArtistAlbumSection: Decodable, Hashable {
    let title: String
    let albums: [Album]
}
