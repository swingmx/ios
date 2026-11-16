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
    @Published var sourceName = ""

    enum PlaySource: Equatable {
        case album(String)
        case artist(String)
        case playlist(String)
        case folder(String)
        case search(String)
        case favorite
        case mix(id: String, sourcehash: String)
        case work(String)
        case downloads
        case library
        case home(String)
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
            case .work(let h): "wk:\(h)"
            case .downloads: "downloads"
            case .library: "library"
            case .home(let title): "home:\(title)"
            case .none: ""
            }
        }

        // Reads back a token, for the source saved with the queue.
        init(token: String) {
            func after(_ prefix: String) -> String? {
                token.hasPrefix(prefix) ? String(token.dropFirst(prefix.count)) : nil
            }
            if token == "favorite" { self = .favorite }
            else if token == "downloads" { self = .downloads }
            else if token == "library" { self = .library }
            else if let t = after("home:") { self = .home(t) }
            else if let h = after("al:") { self = .album(h) }
            else if let h = after("ar:") { self = .artist(h) }
            else if let id = after("pl:") { self = .playlist(id) }
            else if let p = after("fo:") { self = .folder(p) }
            else if let q = after("q:") { self = .search(q) }
            else if let h = after("wk:") { self = .work(h) }
            else if let m = after("mix:"), let dot = m.lastIndex(of: ".") {
                // The source hash has no dots, so the last one separates it from the mix id.
                self = .mix(id: String(m[..<dot]), sourcehash: String(m[m.index(after: dot)...]))
            } else { self = .none }
        }

        /// The small caps line above the name in Now Playing.
        var label: String {
            switch self {
            case .album: "Playing from Album"
            case .artist: "Playing from Artist"
            case .playlist: "Playing from Playlist"
            case .folder: "Playing from Folder"
            case .search: "Playing from Search"
            case .mix: "Playing from Mix"
            case .work: "Playing from Work"
            case .favorite, .downloads, .library, .home, .none: "Playing from"
            }
        }
    }

    /// The source's display name when no screen supplied one, worked out from the queue where possible.
    nonisolated static func defaultName(_ source: PlaySource, in tracks: [Track]) -> String {
        switch source {
        case .album(let h): tracks.first { $0.albumhash == h }?.album ?? ""
        case .artist(let h):
            tracks.lazy.compactMap { t in t.artists?.first { $0.artisthash == h }?.name ?? (t.artisthash == h ? t.artist : nil) }
                .first ?? ""
        case .folder(let p): (p as NSString).lastPathComponent
        case .search(let q): "\u{201C}\(q)\u{201D}"
        case .favorite: "Your Favorite Tracks"
        case .downloads: "Downloads"
        case .library: "Your Library"
        case .home(let title): title
        case .playlist, .mix, .work, .none: ""
        }
    }

    @Published var playing = false
    @Published private(set) var handingOff = false
    @Published var switchingTarget = false
    @Published var time: Double = 0
    @Published var total: Double = 0
    @Published var volume: Float = 1 {
        didSet { player?.volume = gain }
    }
    var gain: Float { Self.gain(volume) }

    nonisolated static func gain(_ position: Float) -> Float {
        let pos = min(max(position, 0), 1)
        if pos <= 0 || pos >= 1 { return pos }
        var g = powf(powf(10, -50 / 20), 1 - pos)
        if pos < 0.05 { g *= pos / 0.05 }
        return min(max(g, 0), 1)
    }

    private var timeAnchor: Double = 0
    private var timeAnchorDate: Date = .distantPast
    @Published var shuffle = false
    @Published var loop: LoopMode = .all
    @Published var crossfadeDuration: Double = UserDefaults.standard.double(forKey: "crossfadeDuration") {
        didSet {
            UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration")
        }
    }
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
            case .lossless: "Original"
            }
        }

        var shortLabel: String {
            switch self {
            case .low: "128 kbps"
            case .medium: "256 kbps"
            case .high: "320 kbps"
            case .lossless: "Original"
            }
        }
    }

    /// The transcode bitrate to ask for, if the server transcodes and it's below the file's own.
    private func streamBitrate(for track: Track) -> Int? {
        let kbps: Int? = switch audioQuality {
        case .low: 128
        case .medium: 256
        case .high: 320
        case .lossless: nil
        }
        guard let kbps, API.shared.canTranscode, (track.bitrate ?? .max) > kbps else { return nil }
        return kbps
    }

    enum LoopMode { case off, all, one }

    private var player: AVPlayer?
    private var crossfadePlayer: AVPlayer?
    private var crossfadeObs: Any?
    private var obs: Any?
    private var statusObs: NSKeyValueObservation?
    private var assetLoader: AuthStreamLoader?
    // The outgoing track's loader, kept until its crossfade ends.
    private var fadingLoader: AuthStreamLoader?
    // The play being counted for the server; see PlaySession.
    private var session: PlaySession?
    private var sessionSavedAt = 0.0
    private var lastActivitySecond = -1
    private var lastWidgetCommandAt: TimeInterval = 0

    private enum WidgetPlaybackCommand: String {
        case toggle
        case next
        case previous
    }

    private var wasPlayingBeforeInterruption = false

    private var queueCancellables = Set<AnyCancellable>()

    private var rc: RemoteControl { .shared }
    private(set) var isController = false
    var isLoaded: Bool { player != nil }
    var isAudible: Bool { player?.timeControlStatus == .playing }
    var isStarting: Bool { handingOff }
    private var pendingStart: (time: Double, play: Bool)?

    private init() {
        // Activated only when playback starts, so opening the app doesn't stop other apps' audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        setRemoteCommands(true)
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
        // Optional so queues saved before they were added still load.
        var source: String?
        var sourceName: String?
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
                                 source: source.token, sourceName: sourceName)
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
        sourceName = snap.sourceName ?? Self.defaultName(source, in: snap.queue)
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
        guard !isController, let info = notification.userInfo,
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

    func play(_ track: Track, from list: [Track]? = nil, source: PlaySource, name: String? = nil) {
        if isController {
            rc.replace(list ?? [track], start: list?.firstIndex(of: track) ?? 0, source: source)
            return
        }
        log()
        // A new list without a context isn't credited to the one playing before.
        if source != .none || list != nil {
            self.source = source
            sourceName = name ?? Self.defaultName(source, in: list ?? [track])
        }
        if let list {
            baseOrder = list
            shuffle = false
            queue = list
            index = list.firstIndex(of: track) ?? 0
        }
        current = track
        load(track)
    }

    func playAll(_ tracks: [Track], shuffled: Bool = false, source: PlaySource, name: String? = nil) {
        guard !tracks.isEmpty else { return }
        if isController {
            rc.replace(tracks, start: shuffled ? Int.random(in: tracks.indices) : 0, source: source, shuffled: shuffled)
            return
        }
        log()
        self.source = source
        sourceName = name ?? Self.defaultName(source, in: tracks)
        baseOrder = tracks
        shuffle = shuffled
        queue = shuffled ? SmartShuffle.shuffle(tracks) : tracks
        index = 0
        current = queue[0]
        load(queue[0])
    }

    static let queueAnim: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    func addLast(_ track: Track) {
        if isController { rc.insert([track], next: false); return }
        withAnimation(Self.queueAnim) { queue.append(track) }
        if current == nil {
            index = 0
            current = track
            load(track)
        }
    }

    func addNext(_ track: Track) {
        if isController { rc.insert([track], next: true); return }
        if queue.isEmpty {
            addLast(track)
        } else {
            withAnimation(Self.queueAnim) { queue.insert(track, at: index + 1) }
        }
    }

    func addNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if isController { rc.insert(tracks, next: true); return }
        if queue.isEmpty {
            addLast(tracks)
        } else {
            withAnimation(Self.queueAnim) { queue.insert(contentsOf: tracks, at: index + 1) }
        }
    }

    func addLast(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if isController { rc.insert(tracks, next: false); return }
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
        if isController {
            // shortcut: the rest of the list is appended in list order, not positioned around the track.
            let queued = Set(queue.map(\.trackhash))
            rc.insert(full.filter { !queued.contains($0.trackhash) }, next: false)
            return
        }
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
        if isController { rc.jump(to: i); return }
        log()
        index = i
        current = queue[i]
        load(queue[i])
    }

    func toggleShuffle() {
        if isController { rc.setShuffle(!shuffle); return }
        shuffle.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        applyShuffleToUpcoming()
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
        guard shuffle, !isController, queue.count > 2 else { return }
        let last = queue[index]
        var next = SmartShuffle.shuffle(queue)
        if next.first == last, let i = next.indices.dropFirst().randomElement() { next.swapAt(0, i) }
        queue = next
    }

    func cycleLoop() {
        if isController {
            rc.setRepeat(loop == .off ? .all : loop == .all ? .one : .off)
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        switch loop {
        case .off: loop = .all
        case .all: loop = .one
        case .one: loop = .off
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func next() {
        if isController { rc.command("next"); return }
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
        if isController { rc.command("prev"); return }
        if time > 3 { seek(0); return }
        guard !queue.isEmpty else { return }
        index = index > 0 ? index - 1 : (loop == .all ? queue.count - 1 : 0)
        current = queue[index]
        load(queue[index])
    }

    func toggle() {
        guard !handingOff, !switchingTarget else { return }
        if isController { rc.command("toggle"); return }
        guard player != nil else {
            if let t = current {
                if rc.subscribed { remoteLoad(index, at: time, play: true) } else { load(t) }
                return
            }
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
        if isController {
            rc.command("seek", ["position_ms": Int(max(0, t) * 1000)])
            time = t
            return
        }
        defer { if rc.subscribed { rc.playheadChanged() } }
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
        if isController { return rc.position() }
        guard let p = player, p.timeControlStatus == .playing else { return timeAnchor }
        let dt = min(max(0, date.timeIntervalSince(timeAnchorDate)), 0.5) * Double(p.rate)
        let t = timeAnchor + dt
        return total > 0 ? min(t, total) : t
    }

    var currentSongID: Int {
        guard let hash = current?.trackhash else { return 0 }
        return abs(hash.hashValue)
    }

    private func load(_ track: Track, start: (time: Double, play: Bool)? = nil) {
        pendingStart = start
        handingOff = start != nil
        if !isCrossfading {
            discardPrepared()
            fadeTimer?.invalidate(); fadeTimer = nil
            fadingLoader = nil
        }
        log()
        lastActivitySecond = -1

        time = start?.time ?? 0
        total = 0
        timeAnchor = time
        timeAnchorDate = Date()

        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        statusObs?.invalidate(); statusObs = nil
        if !isCrossfading { player?.pause() }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        if rc.subscribed { rc.playheadChanged() }

        Task { [weak self] in
            await self?.startPlayback(track)
        }
    }

    func remoteLoad(_ i: Int, at seconds: Double, play: Bool) {
        guard queue.indices.contains(i) else { return }
        log()
        index = i
        current = queue[i]
        load(queue[i], start: (seconds, play))
    }

    private func startPlayer() {
        let start = pendingStart ?? (0, true)
        playing = start.play
        resetClock(to: start.time)
        if pendingStart == nil, start.play {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
    }

    /// Seeks to a handed-off position, then plays.
    private func startAt(_ start: (time: Double, play: Bool)) {
        resetClock(to: start.time)
        let p = player
        let tol = CMTime(seconds: 0.2, preferredTimescale: 1000)
        p?.seek(to: CMTime(seconds: start.time, preferredTimescale: 1000), toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === p else { return }
                self.handingOff = false
                if start.play {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    p?.play()
                }
                if self.rc.subscribed { self.rc.playheadChanged() }
            }
        }
    }

    func setController(_ on: Bool) {
        isController = on
        setRemoteCommands(!on)
        guard on else {
            updateNowPlaying()
            return
        }
        log()
        discardPrepared()
        fadeTimer?.invalidate(); fadeTimer = nil
        isCrossfading = false
        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        statusObs?.invalidate(); statusObs = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        player?.pause()
        player = nil
        assetLoader = nil
        fadingLoader = nil
        playing = false
        nowPlayingInfo = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        Task { await ActivityManager.shared.end() }
    }

    func leaveRemote() {
        baseOrder = queue
        if isController { setController(false) }
    }

    private func startPlayback(_ track: Track) async {
        let localURL = DownloadManager.shared.localURL(for: track)
        if FileManager.default.fileExists(atPath: localURL.path) {
            streamCandidates = []
            streamCandidateIndex = 0
            let item = AVPlayerItem(url: localURL)
            observeFailure(of: item, track: track)
            player = AVPlayer(playerItem: item)
            player?.volume = isCrossfading ? 0 : gain

            NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
            setupTimeObserver()
            startPlayer()
            logger.info("✅ Playing offline: \(track.title)")
            beginSession(for: track)
            total = Double(track.duration)
            lastActivitySecond = -1
            updateNowPlaying()
            updateArtwork(track)
            setupCrossfadeObserver()
            await ActivityManager.shared.start(track: track, accentHex: "#FF375F")
            return
        }

        let headers = authHeaders()
        let bitrate = streamBitrate(for: track)
        let candidates = API.shared.streamURLs(track.trackhash, filepath: track.filepath, bitrate: bitrate)
        Log.info("play", "▶︎ \(track.title) — quality=\(audioQuality.rawValue) (\(bitrate.map { "\($0) kbps" } ?? "original")), \(candidates.count) candidates, auth=\(headers["Authorization"] != nil ? "yes" : "NO")")
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
        let transcode = API.isTranscode(url)
        let ext = transcode ? "mp3" : (track.filepath as NSString).pathExtension
        // A VBR MP3 has no seek table, so a mid-track start lands seconds off without a full scan.
        let precise = (pendingStart?.time ?? 0) > 0 && ext.lowercased() == "mp3"
        let asset = AVURLAsset(url: assetURL, options: precise ? [AVURLAssetPreferPreciseDurationAndTimingKey: true] : nil)
        let loader = AuthStreamLoader(realURL: url, headers: streamHeaders, fileExtension: transcode ? nil : ext)
        asset.resourceLoader.setDelegate(loader, queue: AuthStreamLoader.queue)
        assetLoader = loader
        let item = AVPlayerItem(asset: asset)
        observeFailure(of: item, track: track)
        player = AVPlayer(playerItem: item)
        player?.volume = isCrossfading ? 0 : gain
        player?.allowsExternalPlayback = false

        NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
        setupTimeObserver()

        startPlayer()
        Log.info("play", "→ trying candidate \(self.streamCandidateIndex + 1)/\(self.streamCandidates.count) via resource-loader")
        logger.info("▶️ Trying candidate \(self.streamCandidateIndex + 1)/\(self.streamCandidates.count) for \(track.title, privacy: .public)")
        beginSession(for: track)
        total = Double(track.duration)
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(track)
        setupCrossfadeObserver()
        Task { await ActivityManager.shared.start(track: track, accentHex: "#FF375F") }
    }

    private func setupTimeObserver() {
        obs = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let s = self, !s.handingOff else { return }
                let seconds = t.seconds
                s.time = seconds
                s.timeAnchor = seconds
                s.timeAnchorDate = Date()
                if let d = s.player?.currentItem?.duration.seconds, d.isFinite, d != s.total { s.total = d }
                s.tickSession()

                let sec = max(0, Int(seconds))
                if sec != s.lastActivitySecond {
                    s.lastActivitySecond = sec
                    s.updateNowPlaying()
                    if sec % 5 == 0 { s.rc.markPlayed() }
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
                    if let start = s.pendingStart { s.startAt(start) }
                    s.pendingStart = nil
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
        fadingLoader = nil
        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        player?.pause()
        index += 1
        current = queue[index]
        prep.player.volume = gain
        adopt(prep)
    }

    // Makes a prepared player the current one and starts it.
    private func adopt(_ prep: Prepared) {
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
        prep.player.playImmediately(atRate: 1)
        resetClock(to: prep.player.currentTime().seconds)
        playing = true
        beginSession(for: prep.track)
        total = Double(prep.track.duration)
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(prep.track)
        setupCrossfadeObserver()
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
              current != nil, total > 20 else { return }
        let outPoint = total - crossfadeDuration

        if prepared == nil, time >= outPoint - 12, time < outPoint { prepareNext() }
        if time >= outPoint, total - time > 0.5 {
            beginCrossfade(fade: crossfadeDuration)
        }
    }

    private func makeItem(for track: Track) -> (AVPlayerItem, AuthStreamLoader?, [URL])? {
        let localURL = DownloadManager.shared.localURL(for: track)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return (AVPlayerItem(url: localURL), nil, [])
        }
        let candidates = API.shared.streamURLs(track.trackhash, filepath: track.filepath, bitrate: streamBitrate(for: track))
        guard let url = candidates.first else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "swingstream"
        let asset = AVURLAsset(url: comps?.url ?? url)
        let loader = AuthStreamLoader(realURL: url, headers: authHeaders(),
                                      fileExtension: API.isTranscode(url) ? nil : (track.filepath as NSString).pathExtension)
        asset.resourceLoader.setDelegate(loader, queue: AuthStreamLoader.queue)
        return (AVPlayerItem(asset: asset), loader, candidates)
    }

    private func prepareNext() {
        guard let next = upcomingTrack, let (item, loader, candidates) = makeItem(for: next) else { return }
        let p = AVPlayer(playerItem: item)
        p.volume = 0
        p.allowsExternalPlayback = false
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
        fadingLoader = assetLoader
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

        if let prep = prepared, prep.track == next, prep.item.status != .failed {
            prep.player.volume = 0
            adopt(prep)
            runFade(from: oldPlayer, to: prep.player, duration: fade)
        } else {
            discardPrepared()
            Task { [weak self] in
                guard let self else { return }
                await self.startPlayback(next)
                self.player?.volume = 0
                self.runFade(from: oldPlayer, to: self.player, duration: fade)
            }
        }
    }

    private func runFade(from old: AVPlayer?, to new: AVPlayer?, duration: Double) {
        fadeTimer?.invalidate()
        let start = CACurrentMediaTime()
        let d = max(0.5, duration)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak new] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let x = min(1, (CACurrentMediaTime() - start) / d)
                let v = self.gain
                old?.volume = v * Float(cos(x * .pi / 2))
                new?.volume = v * Float(sin(x * .pi / 2))
                if x >= 1 {
                    timer.invalidate()
                    old?.pause()
                    self.fadingLoader = nil
                    new?.volume = v
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

    private func setRemoteCommands(_ enabled: Bool) {
        let c = MPRemoteCommandCenter.shared()
        for command in [c.playCommand, c.pauseCommand, c.nextTrackCommand, c.previousTrackCommand,
                        c.changePlaybackPositionCommand] {
            command.removeTarget(nil)
            command.isEnabled = enabled
        }
        guard enabled else { return }
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

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in Task { @MainActor in AudioPlayer.shared.consumeWidgetCommandIfNeeded() } },
            WidgetPlaybackBridge.notification as CFString, nil, .deliverImmediately
        )
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
        guard !isController, let t = current else { return }
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
        guard !isController, !track.image.isEmpty else { return }

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
