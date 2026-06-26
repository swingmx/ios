import Foundation

extension API {
    func recentlyAdded(_ limit: Int = 20) async throws -> [Album] {
        struct R: Decodable { let items: [Album] }
        return try await (get("/getall/albums", q: ["limit": "\(limit)", "sortby": "created_date", "reverse": "1"]) as R).items
    }

    func recentlyPlayed(_ limit: Int = 20) async throws -> [Album] {
        struct R: Decodable { let items: [Album] }
        return try await (get("/getall/albums", q: ["limit": "\(limit)", "sortby": "lastplayed", "reverse": "1"]) as R).items
    }

    func albums(start: Int = 0, limit: Int = 100) async throws -> AlbumsResponse {
        try await get("/getall/albums", q: ["start": "\(start)", "limit": "\(limit)", "sortby": "created_date", "reverse": "1"])
    }

    func artists(start: Int = 0, limit: Int = 100) async throws -> ArtistsResponse {
        try await get("/getall/artists", q: ["start": "\(start)", "limit": "\(limit)"])
    }

    func album(_ hash: String) async throws -> AlbumDetail {
        struct B: Encodable { let albumhash: String; let limit = 100 }
        return try await post("/album", body: B(albumhash: hash))
    }

    func albumTracks(_ hash: String) async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/album/\(hash)/tracks") as R).tracks
    }

    func artist(_ hash: String) async throws -> ArtistDetail {
        try await get("/artist/\(hash)", q: ["tracklimit": "20", "albumlimit": "30"])
    }

    func artistAlbums(_ hash: String) async throws -> [ArtistAlbumSection] {

        struct R: Decodable {
            let albums: [Album]?
            let singles_and_eps: [Album]?
            let appearances: [Album]?
            let compilations: [Album]?
        }
        let r: R = try await get("/artist/\(hash)/albums", q: ["limit": "100", "all": "true"])
        var sections: [ArtistAlbumSection] = []
        if let a = r.albums, !a.isEmpty { sections.append(ArtistAlbumSection(title: "Albums", albums: a)) }
        if let a = r.singles_and_eps, !a.isEmpty { sections.append(ArtistAlbumSection(title: "Singles & EPs", albums: a)) }
        if let a = r.appearances, !a.isEmpty { sections.append(ArtistAlbumSection(title: "Appearances", albums: a)) }
        if let a = r.compilations, !a.isEmpty { sections.append(ArtistAlbumSection(title: "Compilations", albums: a)) }
        return sections
    }

    func similarArtists(_ hash: String, limit: Int = 12) async throws -> [Artist] {

        try await get("/artist/\(hash)/similar", q: ["limit": "\(limit)"])
    }

    func playlists() async throws -> [Playlist] {

        struct RData: Decodable { let data: [Playlist] }
        struct RPlaylists: Decodable { let playlists: [Playlist] }
        struct RItems: Decodable { let items: [Playlist] }

        let body = try await API.shared.getData("/playlists")
        let dec = JSONDecoder()
        if let r = try? dec.decode(RData.self, from: body) { return r.data }
        if let r = try? dec.decode(RPlaylists.self, from: body) { return r.playlists }
        if let r = try? dec.decode(RItems.self, from: body) { return r.items }
        if let direct = try? dec.decode([Playlist].self, from: body) { return direct }
        return []
    }

    func playlist(_ id: String) async throws -> PlaylistDetail {
        try await get("/playlists/\(id)", q: ["limit": "500"])
    }

    func addTrackToPlaylist(_ id: String, hash: String) async throws {
        struct B: Encodable { let itemhash: String; let itemtype = "tracks" }
        struct E: Decodable {}
        let _: E = try await post("/playlists/\(id)/add", body: B(itemhash: hash))
    }

    func createPlaylist(_ name: String) async throws -> Playlist {
        struct B: Encodable { let name: String }
        return try await post("/playlists/new", body: B(name: name))
    }

    func lyrics(hash: String, path: String) async throws -> LyricsResponse {
        struct B: Encodable { let trackhash: String; let filepath: String }
        return try await post("/lyrics", body: B(trackhash: hash, filepath: path))
    }

    func lyricsRaw(hash: String, path: String) async throws -> Data {
        struct B: Encodable { let trackhash: String; let filepath: String }
        var r = URLRequest(url: URL(string: base + "/lyrics")!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(B(trackhash: hash, filepath: path))
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw APIError.server(h.statusCode) }
        return data
    }

    func fetchLyricsFromServer(hash: String, title: String, artist: String, album: String, path: String) async throws -> LyricsResponse {
        struct B: Encodable {
            let trackhash: String
            let title: String
            let artist: String
            let album: String
            let filepath: String
        }
        return try await post("/plugins/lyrics/search", body: B(trackhash: hash, title: title, artist: artist, album: album, filepath: path))
    }

    func fallbackLyrics(artist: String, title: String, album: String, duration: Int?) async throws -> LyricsResponse {
        var c = URLComponents(string: "https://lrclib.net/api/get")
        c?.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: duration.map(String.init))
        ]

        guard let url = c?.url else { throw APIError.invalidURL }
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(from: url)
        } catch {
            throw APIError.network(error)
        }

        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            throw APIError.server(h.statusCode)
        }

        let payload = try JSONDecoder().decode(LRCLibResponse.self, from: data)
        let synced = payload.syncedLyrics?.isEmpty == false
        let text = synced ? payload.syncedLyrics : payload.plainLyrics
        return LyricsResponse(lyrics: text.map { .string($0) }, synced: synced, copyright: "Lyrics by LRCLIB")
    }

    func search(_ q: String) async throws -> SearchResult {
        try await get("/search/top", q: ["q": q, "limit": "20"])
    }

    func albumColor(_ hash: String) async throws -> String? {
        (try await get("/colors/album/\(hash)") as ColorResponse).color
    }

    func toggleFavorite(hash: String, type: String, add: Bool) async throws {
        struct B: Encodable { let hash: String; let type: String }
        struct E: Decodable {}
        let _: E = try await post(add ? "/favorites/add" : "/favorites/remove",
                                  body: B(hash: hash, type: type))
    }

    func checkFavorite(hash: String, type: String) async throws -> Bool {
        (try await get("/favorites/check", q: ["hash": hash, "type": type]) as FavoriteCheckResponse).is_favorite
    }

    func topTracks(_ period: String = "month", limit: Int = 25) async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/logger/top-tracks", q: ["duration": period, "limit": "\(limit)"]) as R).tracks
    }

    func logPlay(hash: String, ts: Int, dur: Int, source: String) async throws {
        struct B: Encodable { let trackhash: String; let timestamp: Int; let duration: Int; let source: String }
        struct E: Decodable {}
        let _: E = try await post("/logger/track/log", body: B(trackhash: hash, timestamp: ts, duration: dur, source: source))
    }

    func favoritesSummary() async throws -> FavoritesSummary {
        try await get("/favorites", q: ["track_limit": "1", "album_limit": "1", "artist_limit": "1"])
    }

    func favoriteTracks(start: Int = 0, limit: Int = 50) async throws -> FavoriteTracksPage {
        try await get("/favorites/tracks", q: ["start": "\(start)", "limit": "\(limit)"])
    }

    func favoriteAlbums(start: Int = 0, limit: Int = 50) async throws -> FavoriteAlbumsPage {
        try await get("/favorites/albums", q: ["start": "\(start)", "limit": "\(limit)"])
    }

    func favoriteArtists(start: Int = 0, limit: Int = 50) async throws -> FavoriteArtistsPage {
        try await get("/favorites/artists", q: ["start": "\(start)", "limit": "\(limit)"])
    }

    func folder(_ path: String, limit: Int = 500) async throws -> FolderResponse {
        struct B: Encodable { let folder: String; let limit: Int; let start: Int; let tracks_only: Bool }
        return try await post("/folder", body: B(folder: path, limit: limit, start: 0, tracks_only: false))
    }

    func folderTracks(_ path: String) async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/folder/tracks/all", q: ["path": path]) as R).tracks
    }

    func mixTracks(id: String, sourcehash: String, ogSourcehash: String) async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/plugins/mixes/", q: [
            "mixid": id, "sourcehash": sourcehash, "og_sourcehash": ogSourcehash
        ]) as R).tracks
    }

    func homeData(limit: Int = 12) async throws -> Data {
        var c = URLComponents(string: base + "/nothome/")!
        c.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        var r = URLRequest(url: c.url!)
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw APIError.server(h.statusCode) }
        return data
    }

}
