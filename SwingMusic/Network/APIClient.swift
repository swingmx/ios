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
        session = URLSession(configuration: cfg)
    }

    var base: String {
        get { UserDefaults.standard.string(forKey: "server") ?? "http://localhost:1970" }
        set { UserDefaults.standard.set(newValue, forKey: "server") }
    }
    var token: String? {
        get { UserDefaults.standard.string(forKey: "token") }
        set { UserDefaults.standard.set(newValue, forKey: "token") }
    }
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
    func stream(_ hash: String) -> URL? {
        streamURLs(hash).first
    }

    func streamURLs(_ hash: String, filepath: String = "") -> [URL] {
        var paths: [String] = []

        if !filepath.isEmpty, let encodedPath = filepath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            paths.append("/file/\(hash)/legacy?filepath=\(encodedPath)")
        }

        paths.append("/file/\(hash)")
        paths.append("/stream/\(hash)")
        paths.append("/track/\(hash)")

        return paths.compactMap { URL(string: base + $0) }
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
        base = normalizedServer(server)
        struct B: Encodable { let username, password: String }
        let res: AuthResponse = try await post("/auth/login", body: B(username: user, password: pass))
        guard let t = res.accesstoken else { throw APIError.unauthorized }
        token = t
    }

    func loginWithPairingCode(server: String, code: String) async throws {
        base = normalizedServer(server)
        let res: AuthResponse = try await get("/auth/pair", q: ["code": code])
        guard let t = res.accesstoken else { throw APIError.unauthorized }
        token = t
    }

    func logout() { token = nil }

    private func auth(_ r: inout URLRequest) {
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
    }

    func normalizedServer(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var withScheme = trimmed
        if !(trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) {
            let host = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
            let hostNoPort = host.split(separator: ":").first.map(String.init) ?? host
            let isLocal = hostNoPort == "localhost"
                || hostNoPort.hasSuffix(".local")
                || hostNoPort.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            withScheme = (isLocal ? "http://" : "https://") + trimmed
        }
        return withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
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
