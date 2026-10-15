import AVFoundation
import QuartzCore
import Combine
import MediaPlayer
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    private let logger = Logger(subsystem: "com.swingmusic.app", category: "AudioPlayer")

    @Published var current: Track?
    @Published var queue: [Track] = []
    @Published var index: Int = 0
    private var baseOrder: [Track] = []

    @Published var source: PlaySource = .none

    enum PlaySource: Equatable {
        case album(String)
        case artist(String)
        case playlist(String)
        case folder(String)
        case search(String)
        case favorite
        case mix(id: String, sourcehash: String)
        case none

        var token: String {
            switch self {
            case .album(let h): "al:\(h)"
            case .artist(let h): "ar:\(h)"
            case .playlist(let id): "pl:\(id)"
            case .folder(let p): "fo:\(p)"
            case .search(let q): "q:\(q)"
            case .favorite: "favorite"
            case .mix(let id, let sh): "mix:\(id).\(sh)"
            case .none: ""
            }
        }

        // Reads back a token, for the source saved with the queue.
        init(token: String) {
            func after(_ prefix: String) -> String? {
                token.hasPrefix(prefix) ? String(token.dropFirst(prefix.count)) : nil
            }
            if token == "favorite" { self = .favorite }
            else if let h = after("al:") { self = .album(h) }
            else if let h = after("ar:") { self = .artist(h) }
            else if let id = after("pl:") { self = .playlist(id) }
            else if let p = after("fo:") { self = .folder(p) }
            else if let q = after("q:") { self = .search(q) }
            else if let m = after("mix:"), let dot = m.lastIndex(of: ".") {
                // The source hash has no dots, so the last one separates it from the mix id.
                self = .mix(id: String(m[..<dot]), sourcehash: String(m[m.index(after: dot)...]))
            } else { self = .none }
        }
    }

    @Published var playing = false
    @Published var time: Double = 0
    @Published var total: Double = 0
    @Published var volume: Float = 0.8 {
        didSet { player?.volume = volume }
    }

    private var timeAnchor: Double = 0
    private var timeAnchorDate: Date = .distantPast
    @Published var shuffle = false
    @Published var loop: LoopMode = .off
    @Published var crossfadeDuration: Double = UserDefaults.standard.double(forKey: "crossfadeDuration") {
        didSet {
            UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration")
            // A track prepared for AutoMix starts at its cue point, not at the beginning.
            if (oldValue > 0) != (crossfadeDuration > 0), !isCrossfading { discardPrepared() }
        }
    }
    @Published var autoplay: Bool = UserDefaults.standard.bool(forKey: "autoplay") {
        didSet {
            UserDefaults.standard.set(autoplay, forKey: "autoplay")
            if autoplay { extendForAutoplayIfNeeded() }
        }
    }
    private var autoplayLoading = false
    @Published var audioQuality: AudioQuality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "audioQuality") ?? "high") ?? .high {
        didSet {
            UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality")
            if !isCrossfading { discardPrepared() }
        }
    }

    enum AudioQuality: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case lossless = "lossless"

        var label: String {
            switch self {
            case .low: "Low (128 kbps)"
            case .medium: "Medium (256 kbps)"
            case .high: "High (320 kbps)"
            case .lossless: "Lossless"
            }
        }

        var shortLabel: String {
            switch self {
            case .low: "128 kbps"
            case .medium: "256 kbps"
            case .high: "320 kbps"
            case .lossless: "Lossless"
            }
        }
    }

    private var streamParams: (container: String, quality: String) {
        switch audioQuality {
        case .low:      return ("mp3", "128")
        case .medium:   return ("mp3", "256")
        case .high:     return ("mp3", "320")
        case .lossless: return ("flac", "original")
        }
    }

    enum LoopMode { case off, all, one }

    private var player: AVPlayer?
    private var crossfadePlayer: AVPlayer?
    private var crossfadeObs: Any?
    private var obs: Any?
    private var statusObs: NSKeyValueObservation?
    private var assetLoader: AuthStreamLoader?
    // The play being counted for the server; see PlaySession.
    private var session: PlaySession?
    private var sessionSavedAt = 0.0
    private var lastActivitySecond = -1
    private var widgetCommandPoll: AnyCancellable?
    private var lastWidgetCommandAt: TimeInterval = 0

    private enum WidgetPlaybackCommand: String {
        case toggle
        case next
        case previous
    }

    private var wasPlayingBeforeInterruption = false

    private var queueCancellables = Set<AnyCancellable>()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        remote()
        setupWidgetCommandPolling()
        observeInterruptions()
        restoreQueue()
        setupQueuePersistence()
        recoverSession()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveSession() }
        }
    }

    struct QueueSnapshot: Codable {
        var queue: [Track]
        var index: Int
        var shuffle: Bool
        var baseOrder: [Track]
        var time: Double
        // Optional so queues saved before it was added still load.
        var source: String?
    }

    private static let queueStateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue_state.json")
    }()

    private func setupQueuePersistence() {
        Publishers.CombineLatest3($queue, $index, $source)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.persistQueue() }
            .store(in: &queueCancellables)

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.persistQueue() }
        }
    }

    private func persistQueue() {
        guard !queue.isEmpty else {
            try? FileManager.default.removeItem(at: Self.queueStateURL)
            return
        }
        let snap = QueueSnapshot(queue: queue, index: index, shuffle: shuffle, baseOrder: baseOrder, time: time,
                                 source: source.token)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Self.queueStateURL, options: .atomic)
    }

    private func restoreQueue() {
        guard let data = try? Data(contentsOf: Self.queueStateURL),
              let snap = try? JSONDecoder().decode(QueueSnapshot.self, from: data),
              !snap.queue.isEmpty, snap.queue.indices.contains(snap.index) else { return }
        queue = snap.queue
        index = snap.index
        shuffle = snap.shuffle
        baseOrder = snap.baseOrder
        // Without this, plays after a restart were credited to no source and counted as plain tracks.
        source = PlaySource(token: snap.source ?? "")
        current = snap.queue[snap.index]
        total = Double(snap.queue[snap.index].duration)
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = playing
            if playing {
                player?.pause()
                playing = false
                updateNowPlaying()
            }
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
            if wasPlayingBeforeInterruption {
                try? AVAudioSession.sharedInstance().setActive(true)
                if options?.contains(.shouldResume) == true || wasPlayingBeforeInterruption {
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        player?.play()
                        playing = true
                        updateNowPlaying()
                    }
                }
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    func play(_ track: Track, from list: [Track]? = nil, source: PlaySource = .none) {
        log()
        // A new list without a context isn't credited to the one playing before.
        if source != .none || list != nil { self.source = source }
        if let list {
            baseOrder = list
            if shuffle {
                queue = [track] + SmartShuffle.shuffle(list.filter { $0 != track })
                index = 0
            } else {
                queue = list
                index = list.firstIndex(of: track) ?? 0
            }
        }
        current = track
        load(track)
    }

    func playAll(_ tracks: [Track], shuffled: Bool = false, source: PlaySource = .none) {
        guard !tracks.isEmpty else { return }
        log()
        self.source = source
        baseOrder = tracks
        shuffle = shuffled
        queue = shuffled ? SmartShuffle.shuffle(tracks) : tracks
        index = 0
        current = queue[0]
        load(queue[0])
    }

    static let queueAnim: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    func addLast(_ track: Track) {
        withAnimation(Self.queueAnim) { queue.append(track) }
        if current == nil {
            index = 0
            current = track
            load(track)
        }
    }

    func addNext(_ track: Track) {
        if queue.isEmpty {
            addLast(track)
        } else {
            withAnimation(Self.queueAnim) { queue.insert(track, at: index + 1) }
        }
    }

    func addNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            addLast(tracks)
        } else {
            withAnimation(Self.queueAnim) { queue.insert(contentsOf: tracks, at: index + 1) }
        }
    }

    func addLast(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let start = queue.count
        withAnimation(Self.queueAnim) { queue.append(contentsOf: tracks) }
        if current == nil {
            index = start
            current = queue[start]
            load(queue[start])
        }
    }

    // Fills in the rest of a list that started playing from one track (such as all favorites, fetched
    // after playback began) without restarting playback. Ignored once that track is no longer playing.
    func expandQueue(around track: Track, with full: [Track]) {
        guard queue.indices.contains(index), queue[index] == track, current == track else { return }
        let expanded = Self.expandedQueue(queue: queue, index: index, full: full, shuffled: shuffle)
        baseOrder = full
        withAnimation(Self.queueAnim) { queue = expanded.queue }
        index = expanded.index
    }

    // The queue around the playing track once its full list is known. Tracks queued while the list
    // loaded stay right after the playing one. Shuffled, everything else follows in a fresh shuffle;
    // otherwise the full list keeps its order, positioned at the playing track.
    nonisolated static func expandedQueue(queue: [Track], index: Int, full: [Track], shuffled: Bool)
        -> (queue: [Track], index: Int) {
        let current = queue[index]
        let played = Array(queue[..<index])
        let queuedSince = Array(queue[(index + 1)...])
        var taken = Set((played + [current] + queuedSince).map(\.trackhash))
        let rest = full.filter { taken.insert($0.trackhash).inserted }

        if shuffled {
            return (played + [current] + queuedSince + SmartShuffle.shuffle(rest), played.count)
        }
        let order = Dictionary(full.enumerated().map { ($1.trackhash, $0) }, uniquingKeysWith: min)
        let position = order[current.trackhash] ?? -1
        let before = rest.filter { order[$0.trackhash, default: 0] < position }
        let after = rest.filter { order[$0.trackhash, default: 0] > position }
        let head = played + before
        return (head + [current] + queuedSince + after, head.count)
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        log()
        index = i
        current = queue[i]
        load(queue[i])
    }

    func toggleShuffle() {
        shuffle.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        applyShuffleToUpcoming()
        if shuffle { fillUpcoming(to: 10) }
    }

    func fillUpcoming(to count: Int) {
        let missing = count - (queue.count - index - 1)
        guard missing > 0, !autoplayLoading else { return }
        appendLibraryTracks(missing)
    }

    private func applyShuffleToUpcoming() {
        guard !queue.isEmpty, queue.indices.contains(index) else { return }
        let head = Array(queue[0...index])
        let playedHashes = Set(head.map { $0.trackhash })
        let upcoming = Array(queue[(index + 1)...])
        if shuffle {
            queue = head + SmartShuffle.shuffle(upcoming)
        } else {
            let baseSet = Set(baseOrder.map { $0.trackhash })
            let restored = baseOrder.filter { !playedHashes.contains($0.trackhash) }
            let extras = upcoming.filter { !baseSet.contains($0.trackhash) }
            queue = head + restored + extras
        }
    }

    private func reshuffleForNewRound() {
        guard shuffle, queue.count > 2 else { return }
        let last = queue[index]
        var next = SmartShuffle.shuffle(queue)
        if next.first == last, let i = next.indices.dropFirst().randomElement() { next.swapAt(0, i) }
        queue = next
    }

    func cycleLoop() {
        switch loop {
        case .off: loop = .all
        case .all: loop = .one
        case .one: loop = .off
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func appendToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        withAnimation(Self.queueAnim) { queue.append(contentsOf: tracks) }
    }

    func enqueueInterleaved(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        for t in tracks {
            let lower = min(index + 1, queue.count)
            let pos = lower <= queue.count ? Int.random(in: lower...queue.count) : queue.count
            queue.insert(t, at: pos)
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if let prep = prepared, !isCrossfading, prep.item.status != .failed,
           Self.isNextUp(prep.track, queue: queue, index: index, loop: loop) {
            log()
            handOver(to: prep)
            return
        }
        if loop == .one {
            // Each time round is its own play.
            log()
            if let t = current { beginSession(for: t) }
            seek(0); player?.play(); return
        }
        if index < queue.count - 1 { index += 1 }
        else if loop == .all { reshuffleForNewRound(); index = 0 }
        else {
            playing = false
            player?.pause()
            updateNowPlaying()
            Task {
                await ActivityManager.shared.updateState(playing: false, progress: time, duration: total)
            }
            return
        }
        current = queue[index]
        load(queue[index])
    }

    func prev() {
        if time > 3 { seek(0); return }
        guard !queue.isEmpty else { return }
        index = index > 0 ? index - 1 : (loop == .all ? queue.count - 1 : 0)
        current = queue[index]
        load(queue[index])
    }

    func toggle() {
        guard player != nil else {
            if let t = current { load(t); return }
            return
        }
        if playing {
            player?.pause()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
            timeAnchor = time
            timeAnchorDate = Date()
        }
        playing.toggle()
        updateNowPlaying()
        Task {
            await ActivityManager.shared.updateState(playing: playing, progress: time, duration: total)
        }
    }

    func seek(_ t: Double) {
        let tol = CMTime(seconds: 0.2, preferredTimescale: 1000)
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 1000), toleranceBefore: tol, toleranceAfter: tol)
        time = t
        timeAnchor = t
        timeAnchorDate = Date()
    }

    private func resetClock(to seconds: Double) {
        let t = seconds.isFinite ? seconds : 0
        time = t
        timeAnchor = t
        timeAnchorDate = Date()
    }

    func smoothTime(at date: Date = Date()) -> Double {
        guard playing else { return time }
        guard let p = player, p.timeControlStatus == .playing else { return timeAnchor }
        let dt = min(max(0, date.timeIntervalSince(timeAnchorDate)), 0.5) * Double(p.rate)
        let t = timeAnchor + dt
        return total > 0 ? min(t, total) : t
    }

    var currentSongID: Int {
        guard let hash = current?.trackhash else { return 0 }
        return abs(hash.hashValue)
    }

    func extendForAutoplayIfNeeded() {
        guard autoplay, loop == .off, !autoplayLoading, !queue.isEmpty,
              index >= queue.count - 3 else { return }
        appendLibraryTracks(15)
    }

    private func appendLibraryTracks(_ count: Int) {
        guard !autoplayLoading else { return }
        autoplayLoading = true
        let recent = queue.suffix(8)
        let recentArtists = Set(recent.map { $0.artist.lowercased() })
        let inQueue = Set(queue.map(\.trackhash))
        Task { @MainActor in
            defer { self.autoplayLoading = false }
            var library = (try? await API.shared.topTracks("alltime", limit: 500)) ?? []
            if let albums = try? await API.shared.albums(limit: 500).items, !albums.isEmpty {
                await withTaskGroup(of: [Track].self) { group in
                    for a in albums.shuffled().prefix(12) {
                        group.addTask { (try? await API.shared.albumTracks(a.albumhash)) ?? [] }
                    }
                    for await tracks in group { library += tracks }
                }
            }
            var seen = Set<String>()
            library = library.filter { seen.insert($0.trackhash).inserted }
            guard !library.isEmpty else { return }
            let fresh = library.filter { !inQueue.contains($0.trackhash) }
            let sameArtist = fresh.filter { recentArtists.contains($0.artist.lowercased()) }
            let others = fresh.filter { !recentArtists.contains($0.artist.lowercased()) }
            var pick = Array(sameArtist.shuffled().prefix(max(1, count / 3)))
            pick += others.shuffled().prefix(count - pick.count)
            guard !pick.isEmpty else { return }
            self.appendToQueue(SmartShuffle.shuffle(pick))
            print("∞ \(pick.count) Songs aus der Bibliothek angehängt")
        }
    }

    private func load(_ track: Track) {
        extendForAutoplayIfNeeded()
        if !isCrossfading {
            discardPrepared()
            fadeTimer?.invalidate(); fadeTimer = nil
        }
        log()
        lastActivitySecond = -1

        time = 0
        total = 0
        timeAnchor = 0
        timeAnchorDate = Date()

        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        statusObs?.invalidate(); statusObs = nil
        if !isCrossfading { player?.pause() }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        Task { [weak self] in
            await self?.startPlayback(track)
        }
    }

    private func startPlayback(_ track: Track) async {
        let localURL = DownloadManager.shared.localURL(for: track)
        if FileManager.default.fileExists(atPath: localURL.path) {
            streamCandidates = []
            streamCandidateIndex = 0
            let item = AVPlayerItem(url: localURL)
            observeFailure(of: item, track: track)
            player = AVPlayer(playerItem: item)
            player?.volume = volume

            NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
            setupTimeObserver()
            player?.play()
            playing = true
            logger.info("✅ Playing offline: \(track.title)")
            beginSession(for: track)
            total = Double(track.duration)
            time = 0
            lastActivitySecond = -1
            updateNowPlaying()
            updateArtwork(track)
            setupCrossfadeObserver()
            automixDidStart(track)
            await ActivityManager.shared.start(track: track, accentHex: "#FF375F")
            return
        }

        let headers = authHeaders()
        let p = streamParams
        let candidates = API.shared.streamURLs(track.trackhash, filepath: track.filepath, container: p.container, quality: p.quality)
        Log.info("play", "▶︎ \(track.title) — quality=\(audioQuality.rawValue) (\(p.container)/\(p.quality)), \(candidates.count) candidates, auth=\(headers["Authorization"] != nil ? "yes" : "NO")")
        logger.info("Trying \(candidates.count) stream candidates for \(track.trackhash, privacy: .public)")
        for (i, url) in candidates.enumerated() {
            Log.debug("play", "cand[\(i+1)] \(url.absoluteString)")
            logger.info("  [\(i+1)] \(url.absoluteString, privacy: .public)")
        }
        guard !candidates.isEmpty else {
            Log.error("play", "❌ No stream candidates (filepath='\(track.filepath)')")
            player = nil; playing = false
            return
        }

        streamCandidates = candidates
        streamCandidateIndex = 0
        streamHeaders = headers
        playCurrentCandidate(for: track)
    }

    private var streamCandidates: [URL] = []
    private var streamCandidateIndex = 0
    private var streamHeaders: [String: String] = [:]

    private func playCurrentCandidate(for track: Track) {
        guard streamCandidateIndex < streamCandidates.count else {
            Log.error("play", "❌ All \(self.streamCandidates.count) candidates failed for \(track.title) — skipping")
            logger.error("❌ All \(self.streamCandidates.count) candidates failed for \(track.title, privacy: .public) — skipping")
            next()
            return
        }
        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        let url = streamCandidates[streamCandidateIndex]
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "swingstream"
        let assetURL = comps?.url ?? url
        let asset = AVURLAsset(url: assetURL)
        let ext = (track.filepath as NSString).pathExtension
        let loader = AuthStreamLoader(realURL: url, headers: streamHeaders, fileExtension: ext)
        asset.resourceLoader.setDelegate(loader, queue: AuthStreamLoader.queue)
        assetLoader = loader
        let item = AVPlayerItem(asset: asset)
        observeFailure(of: item, track: track)
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        player?.allowsExternalPlayback = false

        NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
        setupTimeObserver()

        player?.play()
        playing = true
        Log.info("play", "→ trying candidate \(self.streamCandidateIndex + 1)/\(self.streamCandidates.count) via resource-loader")
        logger.info("▶️ Trying candidate \(self.streamCandidateIndex + 1)/\(self.streamCandidates.count) for \(track.title, privacy: .public)")
        beginSession(for: track)
        total = Double(track.duration)
        time = 0
        resetClock(to: 0)
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(track)
        setupCrossfadeObserver()
        automixDidStart(track)
        Task { await ActivityManager.shared.start(track: track, accentHex: "#FF375F") }
    }

    private func setupTimeObserver() {
        obs = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let s = self else { return }
                let seconds = t.seconds
                s.time = seconds
                s.timeAnchor = seconds
                s.timeAnchorDate = Date()
                if let d = s.player?.currentItem?.duration.seconds, d.isFinite { s.total = d }
                s.tickSession()

                let sec = max(0, Int(seconds))
                if sec != s.lastActivitySecond {
                    s.lastActivitySecond = sec
                    s.updateNowPlaying()
                    s.checkPreload()
                    s.checkCrossfade()
                    let playing = s.playing, progress = s.time, duration = s.total
                    Task { await ActivityManager.shared.updateState(playing: playing, progress: progress, duration: duration) }
                }
            }
        }
    }

    private func authHeaders() -> [String: String] {
        guard let token = API.shared.token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    private func observeFailure(of item: AVPlayerItem, track: Track) {
        statusObs?.invalidate()
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let err = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let s = self, s.current == track else { return }
                let idx = s.streamCandidateIndex + 1
                switch status {
                case .readyToPlay:
                    Log.info("play", "✅ Candidate \(idx) readyToPlay — \(track.title)")
                case .failed:
                    Log.error("play", "❌ Candidate \(idx)/\(s.streamCandidates.count) failed: \(err ?? "unknown") — trying next")
                    s.logger.error("Candidate \(idx) failed for \(track.title, privacy: .public): \(err ?? "unknown", privacy: .public)")
                    s.streamCandidateIndex += 1
                    s.playCurrentCandidate(for: track)
                default:
                    break
                }
            }
        }
    }

    @objc private func ended() {
        Task { @MainActor in self.log(); self.next() }
    }

    // Plays the preloaded next track straight away, without the gap of loading it from scratch.
    private func handOver(to prep: Prepared) {
        fadeTimer?.invalidate(); fadeTimer = nil
        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        player?.pause()
        index += 1
        current = queue[index]
        extendForAutoplayIfNeeded()
        prep.player.volume = volume
        adopt(prep, rate: 1)
    }

    // Makes a prepared player the current one and starts it.
    private func adopt(_ prep: Prepared, rate: Float) {
        prep.statusObs?.invalidate()
        prepared = nil
        player = prep.player
        assetLoader = prep.loader
        streamCandidates = prep.candidates
        streamCandidateIndex = 0
        streamHeaders = authHeaders()
        observeFailure(of: prep.item, track: prep.track)
        NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: prep.item)
        setupTimeObserver()
        prep.player.playImmediately(atRate: rate)
        resetClock(to: prep.player.currentTime().seconds)
        playing = true
        beginSession(for: prep.track)
        total = Double(prep.track.duration)
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(prep.track)
        setupCrossfadeObserver()
        automixDidStart(prep.track)
        Task { await ActivityManager.shared.start(track: prep.track, accentHex: "#FF375F") }
    }

    private func setupCrossfadeObserver() {
        guard crossfadeDuration > 0 else { return }
    }

    private var isCrossfading = false

    // The next track, loaded ahead so it can start without a gap.
    private struct Prepared {
        let track: Track
        let player: AVPlayer
        let item: AVPlayerItem
        let loader: AuthStreamLoader?
        // Every stream URL for the track, so a failure after handing over can fall back to the others.
        let candidates: [URL]
        var statusObs: NSKeyValueObservation?
    }

    private var prepared: Prepared?

    // How long before the current track ends the next one starts loading.
    nonisolated static let preloadLead: Double = 30

    nonisolated static func shouldPreload(time: Double, total: Double, loop: LoopMode) -> Bool {
        loop != .one && total > 0 && total - time <= preloadLead
    }

    // Whether `track` is what next() would play after the track at `index`.
    nonisolated static func isNextUp(_ track: Track, queue: [Track], index: Int, loop: LoopMode) -> Bool {
        loop != .one && queue.indices.contains(index + 1) && queue[index + 1] == track
    }

    private var fadeTimer: Timer?

    private func automixDidStart(_ track: Track) {
        guard crossfadeDuration > 0 else { return }
        AutoMixStore.shared.load(track.trackhash)
        let upcoming = queue.dropFirst(index + 1).prefix(4).map(\.trackhash)
        AutoMixStore.shared.prepare(Array(upcoming))
    }

    private var upcomingTrack: Track? {
        index + 1 < queue.count ? queue[index + 1] : nil
    }

    private func checkPreload() {
        // The queue may have changed since the track was prepared.
        if let prep = prepared, prep.track != upcomingTrack, !isCrossfading { discardPrepared() }
        guard prepared == nil, !isCrossfading, upcomingTrack != nil,
              Self.shouldPreload(time: time, total: total, loop: loop) else { return }
        prepareNext()
    }

    private func checkCrossfade() {
        guard crossfadeDuration > 0, !isCrossfading, playing, loop != .one,
              let cur = current, total > 20 else { return }
        let info = AutoMixStore.shared.info(for: cur.trackhash)
        let fade = info.map { min($0.mixDuration, 20) } ?? crossfadeDuration
        let outPoint = info.map { min($0.mixOut, total - 1) } ?? (total - crossfadeDuration)

        if prepared == nil, time >= outPoint - 12, time < outPoint { prepareNext() }
        if time >= outPoint, total - time > 0.5 {
            beginCrossfade(fade: fade)
        }
    }

    private func makeItem(for track: Track) -> (AVPlayerItem, AuthStreamLoader?, [URL])? {
        let localURL = DownloadManager.shared.localURL(for: track)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return (AVPlayerItem(url: localURL), nil, [])
        }
        let p = streamParams
        let candidates = API.shared.streamURLs(track.trackhash, filepath: track.filepath, container: p.container, quality: p.quality)
        guard let url = candidates.first else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "swingstream"
        let asset = AVURLAsset(url: comps?.url ?? url)
        let loader = AuthStreamLoader(realURL: url, headers: authHeaders(), fileExtension: (track.filepath as NSString).pathExtension)
        asset.resourceLoader.setDelegate(loader, queue: AuthStreamLoader.queue)
        return (AVPlayerItem(asset: asset), loader, candidates)
    }

    private func prepareNext() {
        guard let next = upcomingTrack, let (item, loader, candidates) = makeItem(for: next) else { return }
        item.audioTimePitchAlgorithm = .timeDomain
        let p = AVPlayer(playerItem: item)
        p.volume = 0
        p.allowsExternalPlayback = false
        if crossfadeDuration > 0, let cue = AutoMixStore.shared.info(for: next.trackhash)?.cueIn, cue > 0.05 {
            p.seek(to: CMTime(seconds: cue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        // Fill the audio buffers once the item can play, so starting it is instant. Prerolling earlier throws.
        let statusObs = p.observe(\.status, options: [.new]) { player, _ in
            guard player.status == .readyToPlay else { return }
            Task { @MainActor in
                guard player.rate == 0, player.status == .readyToPlay else { return }
                player.preroll(atRate: 1)
            }
        }
        prepared = Prepared(track: next, player: p, item: item, loader: loader, candidates: candidates, statusObs: statusObs)
    }

    private func discardPrepared() {
        prepared?.statusObs?.invalidate()
        prepared?.player.pause()
        prepared = nil
    }

    private func beginCrossfade(fade: Double) {
        guard !isCrossfading else { return }
        isCrossfading = true

        let oldPlayer = player
        let oldInfo = current.flatMap { AutoMixStore.shared.info(for: $0.trackhash) }
        if let item = oldPlayer?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        if let o = obs { oldPlayer?.removeTimeObserver(o); obs = nil }

        log()
        guard !queue.isEmpty else { isCrossfading = false; return }
        if index < queue.count - 1 { index += 1 }
        else if loop == .all { reshuffleForNewRound(); index = 0 }
        else { isCrossfading = false; return }
        let next = queue[index]
        current = next

        let newInfo = AutoMixStore.shared.info(for: next.trackhash)
        let startRate: Float = (oldInfo.flatMap { newInfo?.rateToMatch($0) }) ?? 1

        if let prep = prepared, prep.track == next, prep.item.status != .failed {
            prep.player.volume = 0
            adopt(prep, rate: startRate)
            runFade(from: oldPlayer, to: prep.player, duration: fade, startRate: startRate)
        } else {
            discardPrepared()
            Task { [weak self] in
                guard let self else { return }
                await self.startPlayback(next)
                self.player?.volume = 0
                self.runFade(from: oldPlayer, to: self.player, duration: fade, startRate: 1)
            }
        }
    }

    private func runFade(from old: AVPlayer?, to new: AVPlayer?, duration: Double, startRate: Float) {
        fadeTimer?.invalidate()
        let start = CACurrentMediaTime()
        let d = max(0.5, duration)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak old, weak new] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let x = min(1, (CACurrentMediaTime() - start) / d)
                let v = self.volume
                old?.volume = v * Float(cos(x * .pi / 2))
                new?.volume = v * Float(sin(x * .pi / 2))
                if startRate != 1, let n = new, n.rate > 0 {
                    let e = x * x * (3 - 2 * x)
                    n.rate = startRate + (1 - startRate) * Float(e)
                }
                if x >= 1 {
                    timer.invalidate()
                    old?.pause()
                    new?.volume = v
                    if let n = new, n.rate > 0 { n.rate = 1 }
                    self.isCrossfading = false
                }
            }
        }
    }

    // Ends the current play and queues it for the server if enough of it was heard.
    private func log() {
        guard let s = session else { return }
        session = nil
        clearSavedSession()
        if let play = s.play { ScrobbleQueue.shared.record(play) }
    }

    private func beginSession(for track: Track) {
        // A retry of the same track (another stream URL) continues the same play.
        if session?.trackhash == track.trackhash { return }
        log()
        session = PlaySession(trackhash: track.trackhash, source: source.token)
        sessionSavedAt = 0
    }

    private func tickSession() {
        guard session != nil else { return }
        session?.tick(at: Date(), playing: playing && player?.timeControlStatus == .playing)
        // Saved every few seconds of listening, so a play survives the app being closed or killed.
        if let listened = session?.listened, listened - sessionSavedAt >= 5 {
            sessionSavedAt = listened
            saveSession()
        }
    }

    private static let sessionURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("current_play.json")
    }()

    private func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: Self.sessionURL, options: .atomic)
    }

    private func clearSavedSession() {
        try? FileManager.default.removeItem(at: Self.sessionURL)
    }

    // A play still in progress when the app was last closed is queued as it stood then.
    private func recoverSession() {
        guard let data = try? Data(contentsOf: Self.sessionURL) else { return }
        clearSavedSession()
        if let saved = try? JSONDecoder().decode(PlaySession.self, from: data), let play = saved.play {
            ScrobbleQueue.shared.record(play)
        }
    }

    private func remote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.prev() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(e.positionTime) }; return .success
        }
    }

    private func setupWidgetCommandPolling() {
        if let d = UserDefaults(suiteName: "group.swingmusic") {
            lastWidgetCommandAt = d.double(forKey: "widget.commandAt")
        }

        widgetCommandPoll = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.consumeWidgetCommandIfNeeded()
            }
    }

    private func consumeWidgetCommandIfNeeded() {
        guard let d = UserDefaults(suiteName: "group.swingmusic") else { return }

        let timestamp = d.double(forKey: "widget.commandAt")
        guard timestamp > 0, timestamp > lastWidgetCommandAt else { return }
        lastWidgetCommandAt = timestamp

        guard let raw = d.string(forKey: "widget.command"),
              let command = WidgetPlaybackCommand(rawValue: raw) else { return }

        switch command {
        case .toggle:
            toggle()
        case .next:
            next()
        case .previous:
            prev()
        }
    }

    private var nowPlayingInfo: [String: Any] = [:]

    private func updateNowPlaying() {
        PerformanceTracer.shared.measure(.nowPlayingInfo) {
            updateNowPlayingTraced()
        }
    }

    private func updateNowPlayingTraced() {
        guard let t = current else { return }
        var info = nowPlayingInfo
        info[MPMediaItemPropertyTitle] = t.title
        info[MPMediaItemPropertyArtist] = t.allArtists
        info[MPMediaItemPropertyAlbumTitle] = t.album
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPMediaItemPropertyPlaybackDuration] = total
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateArtwork(_ track: Track) {
        guard !track.image.isEmpty else { return }

        let sizes = ["original", "large", "medium", "small", ""]
        var seen = Set<String>()
        let artworkURLs = sizes.compactMap { size -> URL? in
            guard let url = API.shared.img(track.image, size: size) else { return nil }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }

        guard !artworkURLs.isEmpty else { return }

        Task {
            for url in artworkURLs {
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                if let t = API.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }

                guard let (data, response) = try? await Net.session.data(for: req),
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let img = UIImage(data: data) else { continue }

                let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                var info = self.nowPlayingInfo
                info[MPMediaItemPropertyArtwork] = art
                self.nowPlayingInfo = info
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                await ActivityManager.shared.updateImage(data)
                return
            }
        }
    }
}

final class AuthStreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let queue = DispatchQueue(label: "com.swingmusic.assetloader")

    private let realURL: URL
    private let headers: [String: String]
    private let fileExtension: String?
    private let tag: String
    private var reqCounter = 0

    init(realURL: URL, headers: [String: String], fileExtension: String?) {
        self.realURL = realURL
        self.headers = headers
        self.fileExtension = (fileExtension?.isEmpty == false) ? fileExtension : nil
        self.tag = String(realURL.absoluteString.suffix(28))
        super.init()
        Log.info("stream", "Loader init — auth=\(headers["Authorization"] != nil ? "yes" : "NO") ext=\(self.fileExtension ?? "—") url=…\(tag)")
    }

    private func resolveUTI(mime: String) -> String? {
        if let ext = fileExtension, let ut = UTType(filenameExtension: ext.lowercased()) {
            return ut.identifier
        }
        switch mime.lowercased() {
        case "audio/mpeg", "audio/mp3": return UTType.mp3.identifier
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac":
            return (UTType("com.apple.m4a-audio") ?? UTType.mpeg4Audio).identifier
        case "audio/flac", "audio/x-flac": return UTType(filenameExtension: "flac")?.identifier
        case "audio/wav", "audio/x-wav", "audio/wave": return UTType.wav.identifier
        case "audio/ogg", "audio/opus", "application/ogg": return UTType(filenameExtension: "ogg")?.identifier
        case "audio/aiff", "audio/x-aiff": return UTType.aiff.identifier
        default: return UTType(mimeType: mime)?.identifier
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        reqCounter += 1
        let n = reqCounter
        var req = URLRequest(url: realURL)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let d = loadingRequest.dataRequest {
            let start = d.requestedOffset
            let range = d.requestsAllDataToEndOfResource
                ? "bytes=\(start)-" : "bytes=\(start)-\(start + Int64(d.requestedLength) - 1)"
            req.setValue(range, forHTTPHeaderField: "Range")
            Log.debug("stream", "[\(n)] \(range)\(loadingRequest.contentInformationRequest != nil ? " +info" : "")")
        } else {
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        }
        streamer.start(req, for: loadingRequest, n: n)
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        streamer.cancel(loadingRequest)
    }

    private lazy var streamer = StreamDelegate(owner: self)
    private lazy var streamSession: URLSession = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.underlyingQueue = Self.queue
        return URLSession(configuration: .default, delegate: streamer, delegateQueue: q)
    }()

    deinit { streamSession.invalidateAndCancel() }

    fileprivate func fillContentInfo(_ cinfo: AVAssetResourceLoadingContentInformationRequest,
                                     from http: HTTPURLResponse, n: Int) {
        let ctype = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let mime = ctype.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ctype
        if let uti = resolveUTI(mime: mime) { cinfo.contentType = uti }
        cinfo.isByteRangeAccessSupported = true
        let crange = http.value(forHTTPHeaderField: "Content-Range") ?? ""
        if let totalStr = crange.components(separatedBy: "/").last, let total = Int64(totalStr) {
            cinfo.contentLength = total
        } else if let len = http.value(forHTTPHeaderField: "Content-Length"), let total = Int64(len) {
            cinfo.contentLength = total
        }
        Log.debug("stream", "[\(n)] info mime=\(mime) length=\(cinfo.contentLength)")
    }

    fileprivate final class StreamDelegate: NSObject, URLSessionDataDelegate {
        weak var owner: AuthStreamLoader?
        private var requests: [Int: (AVAssetResourceLoadingRequest, Int)] = [:]

        init(owner: AuthStreamLoader) { self.owner = owner }

        func start(_ req: URLRequest, for loadingRequest: AVAssetResourceLoadingRequest, n: Int) {
            guard let owner else { return }
            let task = owner.streamSession.dataTask(with: req)
            AuthStreamLoader.queue.async {
                self.requests[task.taskIdentifier] = (loadingRequest, n)
                task.resume()
            }
        }

        func cancel(_ loadingRequest: AVAssetResourceLoadingRequest) {
            guard let owner else { return }
            AuthStreamLoader.queue.async {
                guard let id = self.requests.first(where: { $0.value.0 === loadingRequest })?.key else { return }
                self.requests[id] = nil
                owner.streamSession.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let (lr, n) = requests[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.error("stream", "[\(n)] HTTP \(code) — failing request")
                requests[dataTask.taskIdentifier] = nil
                lr.finishLoading(with: NSError(domain: "AuthStreamLoader", code: code))
                completionHandler(.cancel)
                return
            }
            if let cinfo = lr.contentInformationRequest { owner?.fillContentInfo(cinfo, from: http, n: n) }
            if lr.dataRequest == nil {
                requests[dataTask.taskIdentifier] = nil
                lr.finishLoading()
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let (lr, _) = requests[dataTask.taskIdentifier], !lr.isCancelled else { return }
            lr.dataRequest?.respond(with: data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let (lr, n) = requests.removeValue(forKey: task.taskIdentifier), !lr.isCancelled, !lr.isFinished else { return }
            if let error, (error as NSError).code != NSURLErrorCancelled {
                Log.error("stream", "[\(n)] \(error.localizedDescription)")
                lr.finishLoading(with: error)
            } else {
                lr.finishLoading()
            }
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            Net.shared.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
        }
    }
}

enum SmartShuffle {
    static func shuffle(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 2 else { return tracks.shuffled() }
        let groups = Dictionary(grouping: tracks) {
            $0.artist.lowercased().trimmingCharacters(in: .whitespaces)
        }
        guard groups.count > 1 else { return tracks.shuffled() }
        var placed: [(position: Double, track: Track)] = []
        placed.reserveCapacity(tracks.count)
        for (_, group) in groups {
            let items = group.shuffled()
            let n = Double(items.count)
            let offset = Double.random(in: 0..<1) / n
            for (i, t) in items.enumerated() {
                let jitter = Double.random(in: -0.15...0.15) / n
                placed.append((offset + Double(i) / n + jitter, t))
            }
        }
        return placed.sorted { $0.position < $1.position }.map(\.track)
    }
}
