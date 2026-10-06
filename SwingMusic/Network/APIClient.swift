import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL, unauthorized, server(Int), decode(Error), network(Error)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .unauthorized: "Unauthorized"
        case .server(let c): "Server error \(c)"
        case .decode(let e): e.localizedDescription
        case .network(let e): e.localizedDescription
        }
    }
}

final class API {
    static let shared = API()
    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.waitsForConnectivity = false
        session = Net.makeSession(cfg)
    }

    var base: String {
        get { UserDefaults.standard.string(forKey: "server") ?? "http://localhost:1970" }
        set { UserDefaults.standard.set(newValue, forKey: "server") }
    }
    static let fallbackServers: [String] = []

    func migrateToSwingServerIfNeeded() async -> Bool {
        guard Self.isHomeLAN(base), base.hasSuffix(":3000"),
              let s = Self.fallbackServers.first, await ping(s) else { return false }
        print("🔁 Umstellung auf den Swing-Server: \(s)")
        base = s
        return true
    }

    @discardableResult
    func ensureReachable() async -> Bool {
        guard Self.isHomeLAN(base) else { return false }
        if await ping(base) { return false }
        for s in Self.fallbackServers where s != base {
            if await ping(s) {
                print("🔁 Server \(base) nicht erreichbar → \(s)")
                base = s
                return true
            }
        }
        return false
    }

    static func isHomeLAN(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        if host.hasSuffix(".local") { return true }
        let o = host.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        return o[0] == 192 && o[1] == 168 || o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1]))
    }

    private func ping(_ b: String) async -> Bool {
        guard let url = URL(string: b) else { return false }
        var r = URLRequest(url: url)
        r.timeoutInterval = 4
        guard let (_, resp) = try? await session.data(for: r) else { return false }
        return resp is HTTPURLResponse
    }

    var token: String? {
        get {
            if let t = cachedToken { return t }
            if UserDefaults.standard.string(forKey: "server") == nil {
                Keychain.set(nil, for: "token")
                return nil
            }
            if let legacy = UserDefaults.standard.string(forKey: "token") {
                Keychain.set(legacy, for: "token")
                UserDefaults.standard.removeObject(forKey: "token")
            }
            cachedToken = Keychain.get("token")
            return cachedToken
        }
        set {
            cachedToken = newValue
            Keychain.set(newValue, for: "token")
            UserDefaults.standard.removeObject(forKey: "token")
        }
    }
    private var cachedToken: String?
    var authed: Bool { token != nil }

    func img(_ path: String, size: String = "medium") -> URL? {
        mediaImageURL(kind: "thumbnail", path: path, size: size)
    }

    func artistImg(_ path: String, size: String = "medium") -> URL? {
        mediaImageURL(kind: "artist", path: path, size: size)
    }

    func mixImg(_ path: String, size: String = "medium") -> URL? {
        mediaImageURL(kind: "mix", path: path, size: size)
    }

    // Custom playlist covers are served at one size only.
    func playlistImg(_ path: String) -> URL? {
        mediaImageURL(kind: "playlist", path: path, size: "")
    }
    func stream(_ hash: String) -> URL? {
        streamURLs(hash).first
    }

    private static let queryValueAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.!~*'()")
        return s
    }()

    func streamURLs(_ hash: String, filepath: String = "", container: String = "mp3", quality: String = "original") -> [URL] {
        var paths: [String] = []

        if !filepath.isEmpty, let enc = filepath.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) {
            paths.append("/file/\(hash)/legacy?filepath=\(enc)&container=\(container)&quality=\(quality)")
            paths.append("/file/\(hash)/legacy?filepath=\(enc)&container=mp3&quality=original")
            paths.append("/file/\(hash)/legacy?filepath=\(enc)")
        }

        paths.append("/file/\(hash)")
        paths.append("/stream/\(hash)")
        paths.append("/track/\(hash)")

        var seen = Set<String>()
        let unique = paths.filter { seen.insert($0).inserted }
        return unique.compactMap { URL(string: base + $0) }
    }

    func get<T: Decodable>(_ path: String, q: [String: String] = [:]) async throws -> T {
        var c = URLComponents(string: base + path)!
        if !q.isEmpty { c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var r = URLRequest(url: c.url!)
        auth(&r)
        return try await exec(r)
    }

    func getData(_ path: String, q: [String: String] = [:]) async throws -> Data {
        var c = URLComponents(string: base + path)!
        if !q.isEmpty { c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var r = URLRequest(url: c.url!)
        auth(&r)
        let (data, resp) = try await session.data(for: r)
        if let h = resp as? HTTPURLResponse {
            if h.statusCode == 401 { throw APIError.unauthorized }
            if h.statusCode >= 400 { throw APIError.server(h.statusCode) }
        }
        return data
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var r = URLRequest(url: URL(string: base + path)!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(body)
        auth(&r)
        return try await exec(r)
    }

    func login(server: String, user: String, pass: String) async throws {
        struct B: Encodable { let username, password: String }
        var lastError: Error = APIError.invalidURL
        for candidate in serverCandidates(server) {
            base = candidate
            do {
                let res: AuthResponse = try await post("/auth/login", body: B(username: user, password: pass))
                guard let t = res.accesstoken else { throw APIError.unauthorized }
                token = t
                return
            } catch APIError.network(let e) {
                lastError = APIError.network(e)
            }
        }
        throw lastError
    }

    func loginWithPairingCode(server: String, code: String) async throws {
        var lastError: Error = APIError.invalidURL
        for candidate in serverCandidates(server) {
            base = candidate
            do {
                let res: AuthResponse = try await get("/auth/pair", q: ["code": code])
                guard let t = res.accesstoken else { throw APIError.unauthorized }
                token = t
                return
            } catch APIError.network(let e) {
                lastError = APIError.network(e)
            }
        }
        throw lastError
    }

    func logout() { token = nil }

    private func auth(_ r: inout URLRequest) {
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
    }

    func normalizedServer(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var withScheme = trimmed
        if !(trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) {
            withScheme = Self.defaultScheme(for: trimmed) + "://" + Self.bracketIPv6(trimmed)
        }
        return withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
    }

    static func defaultScheme(for input: String) -> String {
        let hostPort = input.split(separator: "/").first.map(String.init) ?? input
        if hostPort.hasPrefix("[") || hostPort.filter({ $0 == ":" }).count > 1 { return "http" }
        let parts = hostPort.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts.first ?? hostPort
        let port = parts.count > 1 ? Int(parts[1]) : nil
        if let port { return port == 443 ? "https" : "http" }
        let isIPv4 = host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        if host == "localhost" || host.hasSuffix(".local") || isIPv4 || !host.contains(".") { return "http" }
        return "https"
    }

    private static func bracketIPv6(_ input: String) -> String {
        let hostPort = input.split(separator: "/").first.map(String.init) ?? input
        guard !hostPort.hasPrefix("["), hostPort.filter({ $0 == ":" }).count > 1 else { return input }
        return "[" + input + "]"
    }

    func serverCandidates(_ raw: String) -> [String] {
        let first = normalizedServer(raw)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) else { return [first] }
        let other = first.hasPrefix("https://")
            ? "http://" + first.dropFirst("https://".count)
            : "https://" + first.dropFirst("http://".count)
        return [first, String(other)]
    }

    private func exec<T: Decodable>(_ r: URLRequest) async throws -> T {
        let method = r.httpMethod ?? "GET"
        let path = r.url.map { $0.path + ($0.query.map { "?\($0)" } ?? "") } ?? "?"
        let start = Date()

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: r) }
        catch {
            Log.error("net", "\(method) \(path) — network failure: \(error.localizedDescription)")
            throw APIError.network(error)
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        if let h = resp as? HTTPURLResponse {
            if h.statusCode >= 400 {
                Log.error("net", "\(method) \(path) → \(h.statusCode) (\(ms)ms, \(data.count)B)")
            } else {
                Log.debug("net", "\(method) \(path) → \(h.statusCode) (\(ms)ms, \(data.count)B)")
            }
            if h.statusCode == 401 { throw APIError.unauthorized }
            if h.statusCode >= 400 { throw APIError.server(h.statusCode) }
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            Log.error("net", "\(method) \(path) — decode \(T.self) failed: \(error)")
            throw APIError.decode(error)
        }
    }

    private func mediaImageURL(kind: String, path: String, size: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let parts = trimmedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawFile = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawFile.isEmpty else { return nil }

        let encodedFile = rawFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawFile
        let sizeSegment = size.isEmpty ? "" : "\(size)/"

        var urlString = "\(base)/img/\(kind)/\(sizeSegment)\(encodedFile)"
        if parts.count == 2 {
            urlString += "?\(parts[1])"
        }

        return URL(string: urlString)
    }
}

final class Net: NSObject, URLSessionDelegate {
    static let shared = Net()

    static let allowInsecureTLSKey = "allowInsecureTLS"
    static var allowInsecureTLS: Bool {
        get { UserDefaults.standard.bool(forKey: allowInsecureTLSKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowInsecureTLSKey) }
    }

    static var session: URLSession { shared.sharedSession }

    private lazy var sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    static func makeSession(_ cfg: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: cfg, delegate: shared, delegateQueue: nil)
    }

    private static func isConfiguredServer(_ host: String) -> Bool {
        guard let serverHost = URL(string: API.shared.base)?.host, !serverHost.isEmpty else { return false }
        return serverHost.caseInsensitiveCompare(host) == .orderedSame
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard Net.allowInsecureTLS, Net.isConfiguredServer(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
