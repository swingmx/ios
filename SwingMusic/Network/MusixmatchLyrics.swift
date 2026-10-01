import Foundation

actor MusixmatchLyrics {
    static let shared = MusixmatchLyrics()

    private enum Const {
        static let base = "https://apic-desktop.musixmatch.com/ws/1.1/"
        static let appID = "web-desktop-app-v1.0"
        static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
        static let tokenKey = "musixmatchUserToken"
        static let tokenDateKey = "musixmatchUserTokenDate"
        static let tokenMaxAge: TimeInterval = 7 * 24 * 3600
    }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        return URLSession(configuration: cfg)
    }()

    private var cachedToken: String?
    private var misses: Set<String> = []

    private init() {}

    func richsyncLRC(title: String, artist: String, album: String, duration: Int?) async -> String? {
        let key = cacheKey(title: title, artist: artist)
        guard !misses.contains(key) else { return nil }

        if let cached = readCache(key) { return cached }

        do {
            guard let token = try await userToken() else { return nil }
            guard let trackID = try await matchTrack(title: title, artist: artist, album: album,
                                                     duration: duration, token: token) else {
                misses.insert(key)
                return nil
            }
            guard let body = try await richsyncBody(trackID: trackID, duration: duration, token: token) else {
                misses.insert(key)
                return nil
            }
            guard let lrc = Self.makeLRC(fromRichsyncBody: body) else {
                misses.insert(key)
                return nil
            }
            writeCache(key, lrc)
            print("✨ Musixmatch: Wort-für-Wort-Lyrics für \(title) geladen (Track \(trackID)).")
            return lrc
        } catch {
            print("❌ Musixmatch: \(error.localizedDescription)")
            return nil
        }
    }

    func reset() {
        cachedToken = nil
        misses.removeAll()
        UserDefaults.standard.removeObject(forKey: Const.tokenKey)
        UserDefaults.standard.removeObject(forKey: Const.tokenDateKey)
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
    }

    private func userToken() async throws -> String? {
        if let cachedToken { return cachedToken }

        let defaults = UserDefaults.standard
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Const.tokenDateKey)
        if let stored = defaults.string(forKey: Const.tokenKey), age < Const.tokenMaxAge {
            cachedToken = stored
            return stored
        }

        let json = try await request("token.get", query: ["t": UUID().uuidString])
        guard let token = (json?["user_token"] as? String), token.count > 10 else {
            print("⚠️ Musixmatch: Kein Benutzer-Merkmal erhalten.")
            return nil
        }
        cachedToken = token
        defaults.set(token, forKey: Const.tokenKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Const.tokenDateKey)
        return token
    }

    private func matchTrack(title: String, artist: String, album: String,
                            duration: Int?, token: String) async throws -> Int? {
        var query = [
            "q_track": title,
            "q_artist": artist,
            "usertoken": token
        ]
        if !album.isEmpty { query["q_album"] = album }
        if let duration { query["q_duration"] = String(duration) }

        let json = try await request("matcher.track.get", query: query)
        guard let track = json?["track"] as? [String: Any] else { return nil }
        guard (track["has_richsync"] as? Int) == 1 else { return nil }

        if let duration, let length = track["track_length"] as? Int, length > 0 {
            guard abs(length - duration) <= 3 else {
                print("⚠️ Musixmatch: Länge passt nicht (\(length)s statt \(duration)s) — verworfen.")
                return nil
            }
        }
        return track["track_id"] as? Int
    }

    private func richsyncBody(trackID: Int, duration: Int?, token: String) async throws -> String? {
        var query = [
            "track_id": String(trackID),
            "usertoken": token
        ]
        if let duration {
            query["f_richsync_length"] = String(duration)
            query["f_richsync_length_max_deviation"] = "10"
        }

        let json = try await request("track.richsync.get", query: query)
        guard let richsync = json?["richsync"] as? [String: Any] else { return nil }
        return richsync["richsync_body"] as? String
    }

    private func request(_ path: String, query: [String: String]) async throws -> [String: Any]? {
        var components = URLComponents(string: Const.base + path)
        var items = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "app_id", value: Const.appID)
        ]
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = items

        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpShouldHandleCookies = false
        req.setValue(Const.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("x-mxm-token-guid=", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.server(http.statusCode)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any] else { return nil }

        if let header = message["header"] as? [String: Any],
           let status = header["status_code"] as? Int, status != 200 {
            if status != 404 { print("⚠️ Musixmatch \(path): Status \(status)") }
            return nil
        }
        return message["body"] as? [String: Any]
    }

    static func makeLRC(fromRichsyncBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !entries.isEmpty else { return nil }

        var rows: [String] = []
        for entry in entries {
            guard let start = entry["ts"] as? Double else { continue }
            let end = entry["te"] as? Double
            let fullText = (entry["x"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

            var parts: [(time: Double, text: String, space: Bool)] = []
            var hasWord = false
            for chunk in (entry["l"] as? [[String: Any]] ?? []) {
                guard let raw = chunk["c"] as? String else { continue }
                let time = start + ((chunk["o"] as? Double) ?? 0)
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    if !parts.isEmpty { parts[parts.count - 1].space = true }
                    parts.append((time, "", false))
                } else {
                    parts.append((time, text, raw.hasSuffix(" ")))
                    hasWord = true
                }
            }

            guard hasWord else {
                guard !fullText.isEmpty else { continue }
                rows.append("\(stamp(start, bracketed: true))\(fullText)")
                continue
            }

            var row = stamp(start, bracketed: true)
            for part in parts {
                row += stamp(part.time, bracketed: false) + part.text + (part.space ? " " : "")
            }
            if let end, end > parts[parts.count - 1].time {
                row += stamp(end, bracketed: false)
            }
            rows.append(row)
        }

        return rows.isEmpty ? nil : rows.joined(separator: "\n")
    }

    private static func stamp(_ time: Double, bracketed: Bool) -> String {
        let clamped = max(time, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        let millis = Int((clamped - floor(clamped)) * 1000)
        let value = String(format: "%02d:%02d.%03d", minutes, seconds, millis)
        return bracketed ? "[\(value)]" : "<\(value)>"
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MusixmatchLyrics-2", isDirectory: true)
    }

    private func cacheKey(title: String, artist: String) -> String {
        let raw = "\(artist.lowercased())|\(title.lowercased())"
        return raw.unicodeScalars.reduce(into: "") { result, scalar in
            result.append(CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_")
        }
    }

    private func readCache(_ key: String) -> String? {
        let url = Self.cacheDirectory.appendingPathComponent("\(key).lrc")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func writeCache(_ key: String, _ lrc: String) {
        let dir = Self.cacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lrc.write(to: dir.appendingPathComponent("\(key).lrc"), atomically: true, encoding: .utf8)
    }
}
