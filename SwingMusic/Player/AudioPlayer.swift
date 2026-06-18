import AVFoundation
import Combine
import MediaPlayer
import os
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    private let logger = Logger(subsystem: "com.swingmusic.app", category: "AudioPlayer")

    @Published var current: Track?
    @Published var queue: [Track] = []
    @Published var index: Int = 0

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
    }

    @Published var playing = false
    @Published var time: Double = 0
    @Published var total: Double = 0
    @Published var volume: Float = 0.8

    private var timeAnchor: Double = 0
    private var timeAnchorDate: Date = .distantPast
    @Published var shuffle = false
    @Published var loop: LoopMode = .off
    @Published var crossfadeDuration: Double = 0
    @Published var audioQuality: AudioQuality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "audioQuality") ?? "high") ?? .high {
        didSet { UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality") }
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

    enum LoopMode { case off, all, one }

    private var player: AVPlayer?
    private var crossfadePlayer: AVPlayer?
    private var crossfadeObs: Any?
    private var obs: Any?
    private var started: Date?
    private var startTS = 0
    private var lastActivitySecond = -1
    private var widgetCommandPoll: AnyCancellable?
    private var lastWidgetCommandAt: TimeInterval = 0

    private enum WidgetPlaybackCommand: String {
        case toggle
        case next
        case previous
    }

    private var wasPlayingBeforeInterruption = false

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        remote()
        setupWidgetCommandPolling()
        observeInterruptions()
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
        if source != .none { self.source = source }
        if let list { queue = list; index = list.firstIndex(of: track) ?? 0 }
        current = track
        load(track)
    }

    func playAll(_ tracks: [Track], shuffled: Bool = false, source: PlaySource = .none) {
        guard !tracks.isEmpty else { return }
        log()
        self.source = source
        queue = shuffled ? tracks.shuffled() : tracks
        index = 0
        current = queue[0]
        load(queue[0])
    }

    func addLast(_ track: Track) {
        queue.append(track)
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
            queue.insert(track, at: index + 1)
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if loop == .one { seek(0); player?.play(); return }
        if shuffle { index = Int.random(in: 0..<queue.count) }
        else if index < queue.count - 1 { index += 1 }
        else if loop == .all { index = 0 }
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
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        time = t
        timeAnchor = t
        timeAnchorDate = Date()
    }

    func smoothTime(at date: Date = Date()) -> Double {
        guard playing else { return time }
        let dt = min(max(0, date.timeIntervalSince(timeAnchorDate)), 0.12)
        let t = timeAnchor + dt
        return total > 0 ? min(t, total) : t
    }

    private func load(_ track: Track) {
        log()
        lastActivitySecond = -1
        if let o = obs { player?.removeTimeObserver(o); obs = nil }
        if !isCrossfading { player?.pause() }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        Task { [weak self] in
            await self?.startPlayback(track)
        }
    }

    private func startPlayback(_ track: Track) async {

        let localURL = DownloadManager.shared.localURL(for: track)
        if FileManager.default.fileExists(atPath: localURL.path) {
            let item = AVPlayerItem(url: localURL)
            player = AVPlayer(playerItem: item)
            player?.volume = volume

            NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
            setupTimeObserver()
            player?.play()
            playing = true
            logger.info("✅ Playing offline: \(track.title)")
            started = Date()
            startTS = Int(Date().timeIntervalSince1970)
            total = Double(track.duration)
            time = 0
            lastActivitySecond = -1
            updateNowPlaying()
            updateArtwork(track)
            setupCrossfadeObserver()
            await ActivityManager.shared.start(track: track, accentHex: "#FF375F")
            return
        }

        let headers = authHeaders()
        let candidates = API.shared.streamURLs(track.trackhash, filepath: track.filepath)
        logger.info("Trying \(candidates.count) stream candidates for \(track.trackhash, privacy: .public)")
        for (i, url) in candidates.enumerated() {
            logger.info("  [\(i+1)] \(url.absoluteString, privacy: .public)")
        }

        guard let workingURL = await firstReachableURL(from: candidates, headers: headers) else {
            logger.error("❌ No reachable stream endpoint for \(track.trackhash, privacy: .public)")
            player = nil
            playing = false
            return
        }

        let asset = AVURLAsset(url: workingURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player?.volume = volume

        NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
        setupTimeObserver()

        player?.play()
        playing = true
        logger.info("✅ Now playing: \(track.title) from \(workingURL.path, privacy: .public)")
        started = Date()
        startTS = Int(Date().timeIntervalSince1970)
        total = Double(track.duration)
        time = 0
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(track)
        setupCrossfadeObserver()
        await ActivityManager.shared.start(track: track, accentHex: "#FF375F")
    }

    private func setupTimeObserver() {
        obs = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let s = self else { return }
                s.time = t.seconds
                s.timeAnchor = t.seconds
                s.timeAnchorDate = Date()
                if let d = s.player?.currentItem?.duration.seconds, d.isFinite { s.total = d }

                let sec = max(0, Int(s.time))
                if sec != s.lastActivitySecond {
                    s.lastActivitySecond = sec
                    s.updateNowPlaying()
                    s.checkCrossfade()
                    await ActivityManager.shared.updateState(playing: s.playing, progress: s.time, duration: s.total)
                }
            }
        }
    }

    private func authHeaders() -> [String: String] {
        guard let token = API.shared.token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    private func firstReachableURL(from urls: [URL], headers: [String: String]) async -> URL? {
        for url in urls {
            let result = await probe(url, headers: headers)
            if result.reachable {
                logger.info("✅ Found working endpoint: \(url.path, privacy: .public)")
                return url
            }
            if let code = result.statusCode {
                logger.warning("  ❌ \(url.path, privacy: .public) → \(code)")
            } else {
                logger.warning("  ❌ \(url.path, privacy: .public) → no response")
            }
        }
        return nil
    }

    private func probe(_ url: URL, headers: [String: String]) async -> (reachable: Bool, statusCode: Int?) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse else {
                logger.warning("Probe got no HTTP response for \(url.absoluteString, privacy: .public)")
                return (false, nil)
            }

            let ok = (200...299).contains(h.statusCode) || h.statusCode == 206 || h.statusCode == 416
            logger.info("Probe status=\(h.statusCode) (\(ok ? "OK" : "FAIL")) for \(url.absoluteString, privacy: .public)")
            return (ok, h.statusCode)
        } catch let e {
            logger.warning("Probe error: \(e.localizedDescription, privacy: .public)")
            return (false, nil)
        }
    }

    @objc private func ended() {
        Task { @MainActor in self.log(); self.next() }
    }

    private func setupCrossfadeObserver() {
        guard crossfadeDuration > 0 else { return }

    }

    private var isCrossfading = false

    private func checkCrossfade() {
        guard crossfadeDuration > 0, !isCrossfading, playing, total > crossfadeDuration else { return }
        let remaining = total - time
        if remaining <= crossfadeDuration && remaining > 0.5 {
            beginCrossfade()
        }
    }

    private func beginCrossfade() {
        guard !isCrossfading else { return }
        isCrossfading = true

        let oldPlayer = player
        let fadeDuration = crossfadeDuration
        let originalVol = volume

        if let item = oldPlayer?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }

        let fadeSteps = 20
        let interval = fadeDuration / Double(fadeSteps)
        let volumeStep = originalVol / Float(fadeSteps)

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            Task { @MainActor [weak oldPlayer] in
                guard let p = oldPlayer else { timer.invalidate(); return }
                let newVol = p.volume - volumeStep
                if newVol <= 0 {
                    p.pause()
                    timer.invalidate()
                } else {
                    p.volume = max(0, newVol)
                }
            }
        }

        log()

        guard !queue.isEmpty else { isCrossfading = false; return }
        if shuffle { index = Int.random(in: 0..<queue.count) }
        else if index < queue.count - 1 { index += 1 }
        else if loop == .all { index = 0 }
        else { isCrossfading = false; return }

        current = queue[index]

        if let o = obs { player?.removeTimeObserver(o); obs = nil }

        Task { [weak self] in
            guard let self else { return }
            await self.startPlayback(self.queue[self.index])
            self.isCrossfading = false
        }
    }

    private func log() {
        guard let t = current, let s = started else { return }
        let d = Int(Date().timeIntervalSince(s))

        if d >= 5 {
            ScrobbleQueue.shared.record(trackhash: t.trackhash, timestamp: startTS, duration: d, source: source.token)
        }
        started = nil
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

    private func updateNowPlaying() {
        guard let t = current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = t.title
        info[MPMediaItemPropertyArtist] = t.artist
        info[MPMediaItemPropertyAlbumTitle] = t.album
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPMediaItemPropertyPlaybackDuration] = total
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
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

                guard let (data, response) = try? await URLSession.shared.data(for: req),
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let img = UIImage(data: data) else { continue }

                let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                await ActivityManager.shared.updateImage(data)
                return
            }
        }
    }
}
