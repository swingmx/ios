import CryptoKit
import Foundation

enum LyricsSource: String, CaseIterable, Sendable {
    case qq, kugou, netease

    var displayName: String {
        switch self {
        case .qq: "QQ Music"
        case .kugou: "Kugou"
        case .netease: "NetEase Cloud Music"
        }
    }
}

struct LyricsCandidate: Sendable {
    let source: LyricsSource
    let id: String
    var hash: String = ""
    let title: String
    let artists: [String]
    let album: String
    let durationMs: Int
}

protocol LyricsProvider: Sendable {
    var source: LyricsSource { get }
    func search(_ keyword: String) async throws -> [LyricsCandidate]
    func lyrics(for c: LyricsCandidate) async throws -> [TimedLine]?
}

enum LyricsHTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    static func json(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    static func query(_ items: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return items.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }
}

private func str(_ v: Any?) -> String {
    switch v {
    case let s as String: s
    case let n as NSNumber: n.stringValue
    default: ""
    }
}
private func int(_ v: Any?) -> Int {
    switch v {
    case let n as NSNumber: n.intValue
    case let s as String: Int(s) ?? 0
    default: 0
    }
}

actor QQMusicProvider: LyricsProvider {
    nonisolated let source = LyricsSource.qq
    private var comm: [String: Any] = [
        "ct": 11, "cv": "1003006", "v": "1003006", "os_ver": "15",
        "phonetype": "24122RKC7C",
        "rom": "Redmi/miro/miro:15/AE3A.240806.005/OS2.0.105.0.VOMCNXM:user/release-keys",
        "tmeAppID": "qqmusiclight", "nettype": "NETWORK_WIFI", "udid": "0",
    ]
    private var hasSession = false
    private var pausedUntil = Date.distantPast

    private func request(_ method: String, _ module: String, _ param: [String: Any],
                         retry: Bool = true) async throws -> [String: Any] {
        guard Date() >= pausedUntil else { throw URLError(.resourceUnavailable) }
        if !hasSession, method != "GetSession" { try await startSession() }
        let body: [String: Any] = ["comm": comm, "request": ["method": method, "module": module, "param": param]]
        var req = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: .withoutEscapingSlashes)
        req.setValue("tmeLoginType=-1;", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("okhttp/3.14.9", forHTTPHeaderField: "User-Agent")
        let json = try await LyricsHTTP.json(req)
        let r = json["request"] as? [String: Any]
        guard int(json["code"]) == 0, let r, int(r["code"]) == 0, let data = r["data"] as? [String: Any] else {
            if retry, method != "GetSession" {
                hasSession = false
                try await Task.sleep(for: .milliseconds(400))
                return try await request(method, module, param, retry: false)
            }
            if method != "GetSession" { pausedUntil = Date().addingTimeInterval(120) }
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func startSession() async throws {
        let data = try await request("GetSession", "music.getSession.session", ["caller": 0, "uid": "0", "vkey": 0])
        guard let s = data["session"] as? [String: Any] else { throw URLError(.badServerResponse) }
        comm["uid"] = s["uid"]; comm["sid"] = s["sid"]; comm["userip"] = s["userip"]
        hasSession = true
    }

    func search(_ keyword: String) async throws -> [LyricsCandidate] {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let searchID = Int.random(in: 1...20) * 18_014_398_509_481_984
            + Int.random(in: 0...4_194_304) * 4_294_967_296 + ms % 86_400_000
        let data = try await request("DoSearchForQQMusicLite", "music.search.SearchCgiService", [
            "search_id": String(searchID), "remoteplace": "search.android.keyboard", "query": keyword,
            "search_type": 0, "num_per_page": 20, "page_num": 1, "highlight": 0, "nqc_flag": 0,
            "page_id": 1, "grp": 1,
        ])
        let items = ((data["body"] as? [String: Any])?["item_song"] as? [[String: Any]]) ?? []
        return items.map { s in
            LyricsCandidate(
                source: .qq, id: str(s["id"]),
                title: str(s["title"]),
                artists: ((s["singer"] as? [[String: Any]]) ?? []).map { str($0["name"]) }.filter { !$0.isEmpty },
                album: str((s["album"] as? [String: Any])?["name"]),
                durationMs: int(s["interval"]) * 1000)
        }
    }

    func lyrics(for c: LyricsCandidate) async throws -> [TimedLine]? {
        guard let songID = Int(c.id) else { return nil }
        let b64 = { (s: String) in Data(s.utf8).base64EncodedString() }
        let data = try await request("GetPlayLyricInfo", "music.musichallSong.PlayLyricInfo", [
            "albumName": b64(c.album), "crypt": 1, "ct": 19, "cv": 2111,
            "interval": c.durationMs / 1000, "lrc_t": 0, "qrc": 1, "qrc_t": 0,
            "roma": 0, "roma_t": 0, "singerName": b64(c.artists.joined(separator: "/")),
            "songID": songID, "songName": b64(c.title), "trans": 0, "trans_t": 0, "type": 0,
        ])
        let hex = str(data["lyric"])
        guard !hex.isEmpty, let text = LyricsCrypto.qrcDecrypt(hex: hex) else { return nil }
        let lines = LyricsFormats.parseQQ(text)
        return lines.isEmpty ? nil : lines
    }
}

struct KugouProvider: LyricsProvider {
    let source = LyricsSource.kugou
    private static let salt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"

    private static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func request(_ url: String, _ params: [String: String], module: String,
                         extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let mid = Self.md5(String(nowMs))
        var p: [String: String]
        if module == "Lyric" {
            p = ["appid": "3116", "clientver": "11070"]
        } else {
            p = ["userid": "0", "appid": "3116", "token": "", "clienttime": String(nowMs / 1000),
                 "iscorrection": "1", "uuid": "-", "mid": mid, "dfid": "-", "clientver": "11070",
                 "platform": "AndroidFilter"]
        }
        p.merge(params) { _, new in new }
        let sorted = p.sorted { $0.key < $1.key }
        p["signature"] = Self.md5(Self.salt + sorted.map { "\($0.key)=\($0.value)" }.joined() + Self.salt)

        let items = p.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        guard let u = URL(string: url + "?" + LyricsHTTP.query(items)) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("Android14-1070-11070-201-0-\(module)-wifi", forHTTPHeaderField: "User-Agent")
        req.setValue("1", forHTTPHeaderField: "KG-Rec")
        req.setValue("1", forHTTPHeaderField: "KG-RC")
        req.setValue(String(nowMs), forHTTPHeaderField: "KG-CLIENTTIMEMS")
        req.setValue(mid, forHTTPHeaderField: "mid")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        let json = try await LyricsHTTP.json(req)
        let code = json["error_code"].map(int) ?? 0
        guard code == 0 || code == 200 else { throw URLError(.badServerResponse) }
        return json
    }

    func search(_ keyword: String) async throws -> [LyricsCandidate] {
        let json = try await request("https://complexsearch.kugou.com/v2/search/song",
                                     ["sorttype": "0", "keyword": keyword, "pagesize": "20", "page": "1"],
                                     module: "SearchSong", extraHeaders: ["x-router": "complexsearch.kugou.com"])
        let lists = ((json["data"] as? [String: Any])?["lists"] as? [[String: Any]]) ?? []
        return lists.map { s in
            LyricsCandidate(
                source: .kugou, id: str(s["ID"]), hash: str(s["FileHash"]),
                title: str(s["SongName"]),
                artists: ((s["Singers"] as? [[String: Any]]) ?? []).map { str($0["name"]) }.filter { !$0.isEmpty },
                album: str(s["AlbumName"]),
                durationMs: int(s["Duration"]) * 1000)
        }
    }

    func lyrics(for c: LyricsCandidate) async throws -> [TimedLine]? {
        let list = try await request("https://lyrics.kugou.com/v1/search", [
            "album_audio_id": c.id, "duration": String(c.durationMs), "hash": c.hash,
            "keyword": "\(c.artists.joined(separator: "、")) - \(c.title)", "lrctxt": "1", "man": "no",
        ], module: "Lyric")
        guard let best = (list["candidates"] as? [[String: Any]])?.first else { return nil }
        let dl = try await request("https://lyrics.kugou.com/download", [
            "accesskey": str(best["accesskey"]), "charset": "utf8", "client": "mobi", "fmt": "krc",
            "id": str(best["id"]), "ver": "1",
        ], module: "Lyric")
        let content = str(dl["content"])
        guard !content.isEmpty else { return nil }
        if int(dl["contenttype"]) == 2 { return nil }
        guard let krc = LyricsCrypto.krcDecrypt(base64: content) else { return nil }
        let lines = LyricsFormats.parseKRC(krc)
        return lines.isEmpty ? nil : lines
    }
}

struct NetEaseProvider: LyricsProvider {
    let source = LyricsSource.netease

    private func get(_ path: String, _ items: [(String, String)]) async throws -> [String: Any] {
        guard let u = URL(string: "https://music.163.com\(path)?" + LyricsHTTP.query(items)) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        return try await LyricsHTTP.json(req)
    }

    func search(_ keyword: String) async throws -> [LyricsCandidate] {
        let json = try await get("/api/search/get", [("s", keyword), ("type", "1"), ("limit", "20"), ("offset", "0")])
        let songs = ((json["result"] as? [String: Any])?["songs"] as? [[String: Any]]) ?? []
        return songs.map { s in
            LyricsCandidate(
                source: .netease, id: str(s["id"]),
                title: str(s["name"]),
                artists: ((s["artists"] as? [[String: Any]]) ?? []).map { str($0["name"]) }.filter { !$0.isEmpty },
                album: str((s["album"] as? [String: Any])?["name"]),
                durationMs: int(s["duration"]))
        }
    }

    func lyrics(for c: LyricsCandidate) async throws -> [TimedLine]? {
        let json = try await get("/api/song/lyric", [("id", c.id), ("lv", "-1"), ("kv", "-1"), ("yv", "-1")])
        let yrc = str((json["yrc"] as? [String: Any])?["lyric"])
        guard !yrc.isEmpty else { return nil }
        let lines = LyricsFormats.parseYRC(yrc)
        return lines.isEmpty ? nil : lines
    }
}
