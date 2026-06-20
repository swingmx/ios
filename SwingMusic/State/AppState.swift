import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var authed = false
    @Published var tab: Tab = .home
    @Published var accent: Color = .white

    @Published var recentAdded: [Album] = []
    @Published var recentPlayed: [Album] = []
    @Published var topTracks: [Track] = []
    @Published var allAlbums: [Album] = []
    @Published var allArtists: [Artist] = []
    @Published var allPlaylists: [Playlist] = []
    @Published var favTracks: [Track] = []
    @Published var favAlbums: [Album] = []
    @Published var favArtists: [Artist] = []

    @Published var showPlayer = false
    @Published var showLyrics = false
    @Published var lyrics: ParsedLyrics?
    @Published var lyricIdx = 0
    @Published var loadingLyrics = false

    @Published var colorCache: [String: Color] = [:]
    @Published var currentBGImage: UIImage?
    @Published var appearanceMode: AppearanceMode = .dark

    enum AppearanceMode: String, CaseIterable {
        case system = "System"
        case dark = "Dark"
        case light = "Light"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .dark: .dark
            case .light: .light
            }
        }
    }

    @Published var homePath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var searchPath = NavigationPath()

    let player = AudioPlayer.shared
    private var bag = Set<AnyCancellable>()

    enum Tab: String { case home, library, search, settings }

    enum NavTarget: Equatable {
        case album(Album)
        case artist(Artist)
    }

    @Published var navigationTarget: NavTarget?
    @Published var requestedTrackForPlaylist: Track? = nil
    @Published var scrollOffset: CGFloat = 0
    @Published var scrollingDown = false
    @Published var keyboardVisible = false
    private var lastScrollOffset: CGFloat = 0

    @Published var showBugReport = false
    @Published var currentBugReport: BugReport?

    func beginBugReport() {
        currentBugReport = BugReport.generate()
        Log.info("report", "Bug report opened — \(currentBugReport?.id ?? "?")")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if showPlayer {
            showPlayer = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showBugReport = true
            }
        } else {
            showBugReport = true
        }
    }

    func updateScroll(_ offset: CGFloat) {
        let delta = offset - lastScrollOffset

        if abs(delta) > 2 {
            scrollingDown = delta < 0
        }
        lastScrollOffset = offset
        scrollOffset = offset
    }

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.keyboardVisible = true }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.keyboardVisible = false }
            .store(in: &bag)
        authed = API.shared.authed
        player.$current
            .removeDuplicates()
            .sink { [weak self] t in Task { @MainActor in if let t { await self?.onTrack(t) } } }
            .store(in: &bag)
        player.$time
            .sink { [weak self] t in self?.syncLyric(t) }
            .store(in: &bag)
    }

    func login(server: String, user: String, pass: String) async throws {
        do {
            try await API.shared.login(server: server, user: user, pass: pass)
        } catch {
            Log.error("auth", "Login failed for \(server): \(error.localizedDescription)")
            throw error
        }
        Log.info("auth", "Logged in to \(API.shared.base)")
        authed = true
        Task { await loadHome() }
    }

    func loginWithToken(server: String, token: String) async throws {
        API.shared.base = API.shared.normalizedServer(server)
        API.shared.token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        let _ = try await API.shared.recentlyAdded(1)
        authed = true
        Task { await loadHome() }
    }

    func loginWithPairingCode(server: String, code: String) async throws {
        try await API.shared.loginWithPairingCode(server: server, code: code)
        authed = true
        Task { await loadHome() }
    }

    func logout() {
        API.shared.logout()
        authed = false
        Task { await ActivityManager.shared.end() }
    }

    func loadHome() async {
        do { let a = try await API.shared.recentlyAdded(); recentAdded = a } catch { print("Error loaded recAdded: \(error)") }
        do { let p = try await API.shared.recentlyPlayed(); recentPlayed = p } catch { print("Error loaded recPlayed: \(error)") }
        do { let t = try await API.shared.topTracks(); topTracks = t } catch { print("Error loaded topTracks: \(error)") }
        do { let pl = try await API.shared.playlists(); allPlaylists = pl } catch { print("Error loaded playlists: \(error)") }
    }

    func loadAlbums() async {
        if !allAlbums.isEmpty { return }
        allAlbums = (try? await API.shared.albums(limit: 300))?.items ?? []
    }

    func loadArtists() async {
        if !allArtists.isEmpty { return }
        allArtists = (try? await API.shared.artists(limit: 300))?.items ?? []
    }

    @Published var homeSections: [HomeSection] = []

    func loadHomeSections() async {
        guard let data = try? await API.shared.homeData(),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        var result: [HomeSection] = []
        for entry in arr {
            guard let key = entry.keys.first,
                  let sec = entry[key] as? [String: Any] else { continue }
            let title = (sec["title"] as? String) ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            let description = (sec["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let rawItems = (sec["items"] as? [[String: Any]]) ?? []

            var items: [HomeItem] = []
            for raw in rawItems {
                guard let type = raw["type"] as? String,
                      let itemObj = raw["item"],
                      let itemData = try? JSONSerialization.data(withJSONObject: itemObj) else { continue }
                switch type {
                case "album":
                    if let a = try? JSONDecoder().decode(Album.self, from: itemData) { items.append(.album(a)) }
                case "artist":
                    if let a = try? JSONDecoder().decode(Artist.self, from: itemData) { items.append(.artist(a)) }
                case "track":
                    if let t = try? JSONDecoder().decode(Track.self, from: itemData) { items.append(.track(t)) }
                case "playlist":
                    if let p = try? JSONDecoder().decode(Playlist.self, from: itemData) { items.append(.playlist(p)) }
                case "mix":
                    if let m = try? JSONDecoder().decode(Mix.self, from: itemData) { items.append(.mix(m)) }
                default:
                    break
                }
            }
            if !items.isEmpty { result.append(HomeSection(id: key, title: title, description: description, items: items)) }
        }
        homeSections = result
    }

    func loadFavorites() async {

        async let tracks = API.shared.favoriteTracks()
        async let albums = API.shared.favoriteAlbums()
        async let artists = API.shared.favoriteArtists()
        favTracks = (try? await tracks) ?? []
        favAlbums = (try? await albums) ?? []
        favArtists = (try? await artists) ?? []
    }

    func loadPlaylists() async {
        do {
            let res = try await API.shared.playlists()
            print("✅ Loaded \(res.count) playlists from server.")
            allPlaylists = res
        } catch {
            print("❌ Failed to load playlists: \(error.localizedDescription)")
            allPlaylists = []
        }
    }

    func color(for hash: String) async -> Color {
        if let c = colorCache[hash] { return c }
        let hex = try? await API.shared.albumColor(hash)
        let c = hex.flatMap { Color(hex: $0) } ?? .white
        colorCache[hash] = c
        return c
    }

    private func onTrack(_ track: Track) async {
        lyrics = nil; lyricIdx = 0; loadingLyrics = true
        let c = await color(for: track.albumhash)
        withAnimation(.easeInOut(duration: 1.0)) { accent = c }

        await loadBGImage(for: track)

        var parsed: ParsedLyrics?

        let localLyrics = DownloadManager.shared.localLyricsURL(for: track)
        if FileManager.default.fileExists(atPath: localLyrics.path) {
            do {
                let content = try String(contentsOf: localLyrics, encoding: .utf8)
                print("✨ Sync: Lokale Lyrics geladen.")
                let parsedLocal = parseLyrics(LyricsResponse(lyrics: .string(content), synced: true, copyright: nil), trackDuration: track.duration, wordByWordForUnsynced: false)
                if !parsedLocal.lines.isEmpty {
                    parsed = parsedLocal
                }
            } catch {
                print("❌ Sync: Fehler beim Laden lokaler Lyrics: \(error)")
            }
        }

        if parsed == nil {
            if let wbw = await fetchWBWLyrics(for: track) {
                parsed = wbw
            }
        }

        if parsed == nil {
            print("🔍 Sync: Starte Lyrics-Abfrage für \(track.title) (Hash: \(track.trackhash))")
            do {
                let serverResponse = try await API.shared.lyrics(hash: track.trackhash, path: track.filepath)
                let serverLyrics = parseLyrics(serverResponse, trackDuration: track.duration, wordByWordForUnsynced: false)
                if !serverLyrics.lines.isEmpty {
                    print("✨ Sync: Server-Lyrics erfolgreich geparst (\(serverLyrics.lines.count) Zeilen).")
                    parsed = serverLyrics
                } else {
                    print("⚠️ Sync: Server-Antwort war leer oder konnte nicht geparst werden.")
                }
            } catch {
                print("❌ Sync: Fehler bei der primären /lyrics Abfrage: \(error.localizedDescription)")
            }
        }

        if parsed == nil || parsed?.synced == false {
            print("🔍 Sync: \(parsed == nil ? "Keine Lyrics" : "Nur unsynced Lyrics") gefunden. Versuche Plugin/lrclib Suche...")
            do {

                if parsed == nil {
                     let serverSearchResponse = try await API.shared.fetchLyricsFromServer(
                        hash: track.trackhash,
                        title: track.title,
                        artist: track.artist,
                        album: track.album,
                        path: track.filepath
                    )
                    let serverSearchLyrics = parseLyrics(serverSearchResponse, trackDuration: track.duration, wordByWordForUnsynced: false)
                    if !serverSearchLyrics.lines.isEmpty {
                        parsed = serverSearchLyrics
                    }
                }

                if parsed == nil || parsed?.synced == false {
                    let remote = try await API.shared.fallbackLyrics(
                        artist: track.artist,
                        title: track.title,
                        album: track.album,
                        duration: track.duration
                    )
                    let fallback = parseLyrics(remote, trackDuration: track.duration, wordByWordForUnsynced: false)
                    if fallback.synced {
                        print("✨ Sync: lrclib hat SYNCED Lyrics geliefert!")
                        parsed = fallback
                    } else if parsed == nil && !fallback.lines.isEmpty {
                        parsed = fallback
                    }
                }
            } catch {
                print("❌ Sync: Fehler bei Fallback-Suche: \(error.localizedDescription)")
            }
        }

        lyrics = parsed
        loadingLyrics = false
        await ActivityManager.shared.updateAccent(c)
    }

    func forceSearchLyrics() async {
        guard let track = player.current else { return }
        loadingLyrics = true
        lyrics = nil

        print("🔍 Force: Manuelle Server-Suche gestartet für \(track.title)")

        if let wbw = await fetchWBWLyrics(for: track) {
            self.lyrics = wbw
            print("✨ Force: Word-by-Word LRC erfolgreich geladen.")
            loadingLyrics = false
            return
        }

        do {
            let res = try await API.shared.fetchLyricsFromServer(
                hash: track.trackhash,
                title: track.title,
                artist: track.artist,
                album: track.album,
                path: track.filepath
            )
            let parsed = parseLyrics(res, trackDuration: track.duration)
            if !parsed.lines.isEmpty {
                self.lyrics = parsed
                print("✨ Force: Lyrics vom Server gefunden.")
            } else {

                let remote = try await API.shared.fallbackLyrics(
                    artist: track.artist,
                    title: track.title,
                    album: track.album,
                    duration: track.duration
                )
                let fallback = parseLyrics(remote, trackDuration: track.duration)
                self.lyrics = fallback.lines.isEmpty ? nil : fallback
                print("✨ Force: local fallback genutzt.")
            }
        } catch {
            print("❌ Force: Fehler bei manueller Suche: \(error)")
        }
        loadingLyrics = false
    }

    private func fetchWBWLyrics(for track: Track) async -> ParsedLyrics? {
        let wbwURL = "\(API.shared.base)/\(track.trackhash).wbw.lrc"
        guard let url = URL(string: wbwURL) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = API.shared.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode == 200 {
                let ct = h.value(forHTTPHeaderField: "Content-Type") ?? ""
                if !ct.hasPrefix("audio/") && data.count < 1_000_000 {
                    if let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii), content.contains("[") {
                        print("✨ Sync: Word-by-Word LRC geladen (\(data.count) bytes)")
                        let wbw = parseLyrics(LyricsResponse(lyrics: .string(content), synced: true, copyright: nil), trackDuration: track.duration, wordByWordForUnsynced: false)
                        return wbw.lines.isEmpty ? nil : wbw
                    }
                }
            }
        } catch {
            print("❌ Sync: WBW fetch fehlgeschlagen: \(error)")
        }
        return nil
    }

    private func syncLyric(_ t: Double) {
        guard let l = lyrics, !l.lines.isEmpty else { return }
        var idx = 0
        for (i, line) in l.lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        if idx != lyricIdx { lyricIdx = idx }
    }

    private func loadBGImage(for track: Track) async {
        guard let url = API.shared.img(track.image) else { return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        withAnimation(.easeInOut(duration: 0.8)) { currentBGImage = img }
    }
}
