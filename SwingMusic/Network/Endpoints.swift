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
        try await get("/artist/\(hash)", q: ["limit": "20", "albumlimit": "30"])
    }

    func artistAlbums(_ hash: String) async throws -> [ArtistAlbumSection] {
        struct R: Decodable { let albums: [ArtistAlbumSection] }
        let r: R = try await get("/artist/\(hash)/albums", q: ["limit": "100"])
        return r.albums
    }

    func similarArtists(_ hash: String, limit: Int = 12) async throws -> [Artist] {

        try await get("/artist/\(hash)/similar", q: ["limit": "\(limit)"])
    }

    func playlists() async throws -> [Playlist] {
        struct R1: Decodable { let playlists: [Playlist] }
        struct R2: Decodable { let items: [Playlist] }
        struct R3: Decodable { let data: [Playlist] }

        if let r = try? await (get("/playlists") as R1) { return r.playlists }
        if let r = try? await (get("/playlists") as R2) { return r.items }
        if let r = try? await (get("/playlists") as R3) { return r.data }

        if let direct = try? await (get("/playlists") as [Playlist]) { return direct }

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
        struct B: Encodable { let itemhash: String; let itemtype: String }
        struct E: Decodable {}
        let _: E = try await post(add ? "/favorites/add" : "/favorites/remove",
                                  body: B(itemhash: hash, itemtype: type))
    }

    func checkFavorite(hash: String, type: String) async throws -> Bool {
        (try await get("/favorites/check", q: ["hash": hash, "type": type]) as FavoriteCheckResponse).is_fav
    }

    func topTracks(_ period: String = "month", limit: Int = 25) async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/logger/top-tracks", q: ["duration": period, "limit": "\(limit)"]) as R).tracks
    }

    func logPlay(hash: String, ts: Int, dur: Int) async throws {
        struct B: Encodable { let trackhash: String; let timestamp: Int; let duration: Int; let source: String }
        struct E: Decodable {}
        let _: E = try await post("/logger/track/log", body: B(trackhash: hash, timestamp: ts, duration: dur, source: "ios"))
    }

    func favoriteTracks() async throws -> [Track] {
        struct R: Decodable { let tracks: [Track] }
        return try await (get("/favorites/tracks", q: ["limit": "200"]) as R).tracks
    }

}
