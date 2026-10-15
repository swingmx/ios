import SwiftUI
import Combine

@MainActor
final class ScrollTracker: ObservableObject {
    static let shared = ScrollTracker()

    @Published var offset: CGFloat = 0
    @Published var down = false
    private var last: CGFloat = 0

    func update(_ newOffset: CGFloat) {
        let delta = newOffset - last
        last = newOffset
        if abs(delta) > 2 {
            let isDown = delta < 0
            if isDown != down { down = isDown }
        }
        if abs(newOffset - offset) > 6 { offset = newOffset }
    }

    func reset() {
        offset = 0
        down = false
        last = 0
    }
}

// Observable rather than ObservableObject so a view re-renders only when a property it read changes.
// With ObservableObject every change re-rendered every view holding AppState, which rebuilt any open
// menu each time and made it flicker.
@MainActor
@Observable
final class AppState {
    let scroll = ScrollTracker.shared
    var authed = false {
        // Plays made while logged out were waiting for a session to send them with.
        didSet { if authed, !oldValue { Task { await ScrobbleQueue.shared.flush() } } }
    }
    var tab: Tab = .home
    var accent: Color = .white

    var recentAdded: [Album] = []
    var recentPlayed: [Album] = []
    var topTracks: [Track] = []
    var allAlbums: [Album] = []
    var allArtists: [Artist] = []
    var allPlaylists: [Playlist] = []
    var favTracks: [Track] = []
    var favAlbums: [Album] = []
    var favArtists: [Artist] = []

    var showPlayer = false
    var showLyrics = false
    var lyrics: ParsedLyrics? { didSet { lyricsRevision &+= 1 } }
    // Changes whenever lyrics is set, for views that need to react to it: ParsedLyrics isn't Equatable.
    private(set) var lyricsRevision = 0
    @ObservationIgnored var lyricIdx = 0
    var loadingLyrics = false

    var colorCache: [String: Color] = [:]
    var currentBGImage: UIImage?
    var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .dark {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var favTracksTotal = 0
    var favAlbumsTotal = 0
    var favArtistsTotal = 0

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

    var homePath = NavigationPath()
    var libraryPath = NavigationPath()
    var favoritesPath = NavigationPath()
    var searchPath = NavigationPath()

    let player = AudioPlayer.shared
    // The playing track's hash, mirrored from the player so views can observe it. Set by the player
    // subscription in init; settable here only so tests can drive it without starting playback.
    var playingTrackHash: String?
    @ObservationIgnored private var bag = Set<AnyCancellable>()

    enum Tab: String { case home, library, favorites, search, settings }

    enum NavTarget: Equatable {
        case album(Album)
        case artist(Artist)
        case folder(Folder)
    }

    var navigationTarget: NavTarget?
    var requestedTrackForPlaylist: Track? = nil
    var keyboardVisible = false

    var showBugReport = false
    var currentBugReport: BugReport?

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
            .sink { [weak self] t in
                self?.playingTrackHash = t?.trackhash
                self?.resetLyrics()
                Task { @MainActor in if let t { await self?.onTrack(t) } }
            }
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

    func loadAlbums(force: Bool = false) async {
        if !allAlbums.isEmpty, !force { return }
        do { allAlbums = try await API.shared.albums(limit: 300).items }
        catch { print("❌ Alben laden: \(error)") }
    }

    func loadArtists(force: Bool = false) async {
        if !allArtists.isEmpty, !force { return }
        do { allArtists = try await API.shared.artists(limit: 300).items }
        catch { print("❌ Artists laden: \(error)") }
    }

    var shufflingLibrary = false

    func shuffleLibrary() async {
        guard !shufflingLibrary else { return }
        shufflingLibrary = true
        let albums = ((try? await API.shared.albums(limit: 5000))?.items ?? allAlbums).shuffled()
        guard !albums.isEmpty else { shufflingLibrary = false; return }

        let batchN = min(8, albums.count)
        var initial: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for a in albums.prefix(batchN) {
                group.addTask { (try? await API.shared.album(a.albumhash))?.tracks ?? [] }
            }
            for await ts in group { initial.append(contentsOf: ts) }
        }
        initial.shuffle()
        shufflingLibrary = false
        guard !initial.isEmpty else { return }

        player.playAll(initial, source: .none)
        player.shuffle = true

        let rest = Array(albums.dropFirst(batchN))
        Task { [weak self] in
            for a in rest {
                let ts = (try? await API.shared.album(a.albumhash))?.tracks ?? []
                if !ts.isEmpty { self?.player.enqueueInterleaved(ts) }
            }
        }
    }

    var homeSections: [HomeSection] = []

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
                if let item = HomeItem.decode(type: type, json: itemData) { items.append(item) }
            }
            if !items.isEmpty { result.append(HomeSection(id: key, title: title, description: description, items: items)) }
        }
        homeSections = result
    }

    private let favPageSize = 50
    // The Favorites screen only previews each group; its See All pages load the rest, favPageSize at a time.
    // The Favorites screen shows only this many of each, newest first, even after its See All pages
    // have loaded more into the same lists.
    let favPreviewTracks = 6
    let favPreviewCards = 24

    // Plays a favorite straight away, then fills the queue with every favorite from one request.
    // Nothing is kept: the list lives only in the queue. Falls back to the loaded favorites offline.
    func playFavorite(_ track: Track) {
        player.play(track, from: [track], source: .favorite)
        Task {
            let all = (try? await API.shared.allFavoriteTracks()) ?? favTracks
            guard player.source == .favorite else { return }
            player.expandQueue(around: track, with: all)
        }
    }

    func loadFavorites() async {
        async let summary = try? await API.shared.favoritesSummary()
        async let tracksPage = try? await API.shared.favoriteTracks(start: 0, limit: favPreviewTracks)
        async let albumsPage = try? await API.shared.favoriteAlbums(start: 0, limit: favPreviewCards)
        async let artistsPage = try? await API.shared.favoriteArtists(start: 0, limit: favPreviewCards)

        favTracks = (await tracksPage)?.tracks ?? []
        favAlbums = (await albumsPage)?.albums ?? []
        favArtists = (await artistsPage)?.artists ?? []

        if let s = await summary {
            favTracksTotal = s.count.tracks
            favAlbumsTotal = s.count.albums
            favArtistsTotal = s.count.artists
        } else {
            favTracksTotal = max(favTracksTotal, favTracks.count)
            favAlbumsTotal = max(favAlbumsTotal, favAlbums.count)
            favArtistsTotal = max(favArtistsTotal, favArtists.count)
        }
    }

    @discardableResult
    func setTrackFavorite(_ track: Track, _ fav: Bool) async -> Bool {
        applyFavorite(track, fav)
        do {
            try await API.shared.toggleFavorite(hash: track.trackhash, type: "track", add: fav)
            return fav
        } catch {
            applyFavorite(track, !fav)
            return !fav
        }
    }

    // Albums and artists: the Favorites lists follow the change, which is undone if the server rejects it.
    // Album and artist favorite changes made in this session, so every screen showing one agrees
    // without refetching it. Like favoriteTrackChanges, they take precedence over the server's flag.
    private(set) var favoriteAlbumChanges: [String: Bool] = [:]
    private(set) var favoriteArtistChanges: [String: Bool] = [:]

    func isAlbumFavorite(_ album: Album) -> Bool {
        favoriteAlbumChanges[album.albumhash]
            ?? album.isFavorite
            ?? favAlbums.contains { $0.albumhash == album.albumhash }
    }

    func isArtistFavorite(_ artist: Artist) -> Bool {
        favoriteArtistChanges[artist.artisthash]
            ?? artist.isFavorite
            ?? favArtists.contains { $0.artisthash == artist.artisthash }
    }

    // Shown straight away, and put back if the server rejects the change. Returns the resulting state.
    @discardableResult
    func setAlbumFavorite(_ album: Album, _ fav: Bool) async -> Bool {
        applyAlbumFavorite(album, fav)
        do {
            try await API.shared.toggleFavorite(hash: album.albumhash, type: "album", add: fav)
            return fav
        } catch {
            applyAlbumFavorite(album, !fav)
            return !fav
        }
    }

    @discardableResult
    func setArtistFavorite(_ artist: Artist, _ fav: Bool) async -> Bool {
        applyArtistFavorite(artist, fav)
        do {
            try await API.shared.toggleFavorite(hash: artist.artisthash, type: "artist", add: fav)
            return fav
        } catch {
            applyArtistFavorite(artist, !fav)
            return !fav
        }
    }

    private func applyAlbumFavorite(_ album: Album, _ fav: Bool) {
        favoriteAlbumChanges[album.albumhash] = fav
        let present = favAlbums.contains { $0.albumhash == album.albumhash }
        if fav && !present {
            favAlbums.insert(album, at: 0)
            favAlbumsTotal += 1
        } else if !fav && present {
            favAlbums.removeAll { $0.albumhash == album.albumhash }
            favAlbumsTotal = max(0, favAlbumsTotal - 1)
        }
    }

    private func applyArtistFavorite(_ artist: Artist, _ fav: Bool) {
        favoriteArtistChanges[artist.artisthash] = fav
        let present = favArtists.contains { $0.artisthash == artist.artisthash }
        if fav && !present {
            favArtists.insert(artist, at: 0)
            favArtistsTotal += 1
        } else if !fav && present {
            favArtists.removeAll { $0.artisthash == artist.artisthash }
            favArtistsTotal = max(0, favArtistsTotal - 1)
        }
    }

    // Favorite changes made in this session, which the track values already on screen do not reflect.
    private(set) var favoriteTrackChanges: [String: Bool] = [:]

    func isCurrentTrack(_ track: Track) -> Bool {
        playingTrackHash == track.trackhash
    }

    func isTrackFavorite(_ track: Track) -> Bool {
        favoriteTrackChanges[track.trackhash]
            ?? track.isFavorite
            ?? favTracks.contains { $0.trackhash == track.trackhash }
    }

    private func applyFavorite(_ track: Track, _ fav: Bool) {
        favoriteTrackChanges[track.trackhash] = fav
        let present = favTracks.contains { $0.trackhash == track.trackhash }
        if fav && !present {
            favTracks.insert(track, at: 0)
            favTracksTotal += 1
        } else if !fav && present {
            favTracks.removeAll { $0.trackhash == track.trackhash }
            favTracksTotal = max(0, favTracksTotal - 1)
        }
    }

    func loadMoreFavoriteTracks() async {
        guard favTracks.count < favTracksTotal else { return }
        guard let page = try? await API.shared.favoriteTracks(start: favTracks.count, limit: favPageSize),
              !page.tracks.isEmpty else { return }
        let existing = Set(favTracks.map { $0.trackhash })
        favTracks.append(contentsOf: page.tracks.filter { !existing.contains($0.trackhash) })
    }

    func loadMoreFavoriteAlbums() async {
        guard favAlbums.count < favAlbumsTotal else { return }
        guard let page = try? await API.shared.favoriteAlbums(start: favAlbums.count, limit: favPageSize),
              !page.albums.isEmpty else { return }
        let existing = Set(favAlbums.map { $0.albumhash })
        favAlbums.append(contentsOf: page.albums.filter { !existing.contains($0.albumhash) })
    }

    func loadMoreFavoriteArtists() async {
        guard favArtists.count < favArtistsTotal else { return }
        guard let page = try? await API.shared.favoriteArtists(start: favArtists.count, limit: favPageSize),
              !page.artists.isEmpty else { return }
        let existing = Set(favArtists.map { $0.artisthash })
        favArtists.append(contentsOf: page.artists.filter { !existing.contains($0.artisthash) })
    }

    func loadPlaylists() async {
        do {
            let res = try await API.shared.playlists()
            print("✅ Loaded \(res.count) playlists from server.")
            // Assigning an unchanged list would still rebuild every view showing playlists.
            if res != allPlaylists { allPlaylists = res }
        } catch {
            // Keep what is already shown: clearing it made playlists vanish whenever the server was unreachable.
            print("❌ Failed to load playlists: \(error.localizedDescription)")
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
        let c = await color(for: track.albumhash)
        withAnimation(.easeInOut(duration: 1.0)) { accent = c }
        await loadBGImage(for: track)
        await ActivityManager.shared.updateAccent(c)
    }

    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTrackHash: String?

    // Lyrics are only fetched when something shows them: the lyrics view asks for them when its own
    // word-by-word search comes up empty or slow. A track change cancels a search still running.
    func loadLyrics(for track: Track) {
        guard track.trackhash == player.current?.trackhash, lyricsTrackHash != track.trackhash else { return }
        lyricsTask?.cancel()
        lyricsTrackHash = track.trackhash
        lyrics = nil
        loadingLyrics = true
        lyricsTask = Task { [weak self] in await self?.fetchLyrics(for: track) }
    }

    private func resetLyrics() {
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsTrackHash = nil
        if lyrics != nil { lyrics = nil }
        lyricIdx = 0
        loadingLyrics = false
    }

    private func fetchLyrics(for track: Track) async {
        let musixmatchTask = wordByWordTask(for: track)
        defer { if Task.isCancelled { musixmatchTask?.cancel() } }

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

        guard !Task.isCancelled, lyricsTrackHash == track.trackhash else { return }
        lyrics = parsed
        loadingLyrics = false

        await upgradeToWordByWord(for: track, task: musixmatchTask)
    }

    private func wordByWordTask(for track: Track) -> Task<String?, Never>? {
        guard UserDefaults.standard.object(forKey: "musixmatchWordByWord") as? Bool ?? true else {
            return nil
        }
        return Task {
            await MusixmatchLyrics.shared.richsyncLRC(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
        }
    }

    private func upgradeToWordByWord(
        for track: Track,
        task: Task<String?, Never>?
    ) async {
        guard let task else { return }
        if let current = lyrics, current.lines.contains(where: { ($0.words?.count ?? 0) > 1 }) {
            task.cancel()
            return
        }

        let lrc = await task.value
        guard let lrc else { return }
        guard !Task.isCancelled, lyricsTrackHash == track.trackhash else { return }

        let parsed = parseLyrics(
            LyricsResponse(lyrics: .string(lrc), synced: true, copyright: "Lyrics by Musixmatch"),
            trackDuration: track.duration
        )
        guard !parsed.lines.isEmpty else { return }

        if let reference = lyrics, reference.synced, reference.lines.count >= 4 {
            if let shift = Self.timeShift(from: parsed, to: reference) {
                if abs(shift) > 0.05 {
                    print("↔️ Musixmatch: um \(String(format: "%.2f", shift)) s ausgerichtet.")
                    lyrics = Self.shifted(parsed, by: shift)
                    syncLyric(player.time)
                    return
                }
            } else if let mine = reference.lines.first?.time,
                      let theirs = parsed.lines.first?.time,
                      abs(mine - theirs) > 2 {
                print("⚠️ Musixmatch: andere Fassung (\(theirs)s statt \(mine)s) — verworfen.")
                return
            }
        }

        lyrics = parsed
        syncLyric(player.time)
    }

    private static func timeShift(
        from candidate: ParsedLyrics,
        to reference: ParsedLyrics
    ) -> TimeInterval? {
        func key(_ text: String) -> String {
            String(
                text.lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                    .prefix(10)
            )
        }

        var referenceTimes: [String: TimeInterval] = [:]
        for line in reference.lines {
            let k = key(line.text)
            guard k.count >= 6 else { continue }
            if referenceTimes[k] == nil { referenceTimes[k] = line.time }
        }

        var deltas: [TimeInterval] = []
        for line in candidate.lines {
            let k = key(line.text)
            guard k.count >= 6, let referenceTime = referenceTimes[k] else { continue }
            deltas.append(referenceTime - line.time)
        }

        guard deltas.count >= 3 else { return nil }
        deltas.sort()
        let median = deltas[deltas.count / 2]

        let agreeing = deltas.filter { abs($0 - median) <= 0.5 }.count
        guard Double(agreeing) / Double(deltas.count) >= 0.7 else { return nil }
        return median
    }

    private static func shifted(
        _ lyrics: ParsedLyrics,
        by shift: TimeInterval
    ) -> ParsedLyrics {
        ParsedLyrics(
            lines: lyrics.lines.map { line in
                LyricLine(
                    time: max(line.time + shift, 0),
                    text: line.text,
                    words: line.words?.map {
                        LyricWord(
                            time: max($0.time + shift, 0),
                            text: $0.text,
                            hasSpace: $0.hasSpace
                        )
                    }
                )
            },
            synced: lyrics.synced,
            copyright: lyrics.copyright
        )
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
            let (data, resp) = try await Net.session.data(for: req)
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
        guard let (data, _) = try? await Net.session.data(for: req),
              let img = UIImage(data: data) else { return }
        withAnimation(.easeInOut(duration: 0.8)) { currentBGImage = img }
    }
}

extension View {
    func squeezeMiniPlayer(_ state: AppState) -> some View {
        self.onScrollGeometryChange(for: CGFloat.self) { geo in
            -geo.contentOffset.y
        } action: { _, newValue in
            state.scroll.update(newValue)
        }
    }
}
