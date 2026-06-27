import AVFoundation
import Combine
import MediaPlayer
import os
import UIKit
import UniformTypeIdentifiers

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
        queue.append(contentsOf: tracks)
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
        started = Date()
        startTS = Int(Date().timeIntervalSince1970)
        total = Double(track.duration)
        time = 0
        lastActivitySecond = -1
        updateNowPlaying()
        updateArtwork(track)
        setupCrossfadeObserver()
        Task { await ActivityManager.shared.start(track: track, accentHex: "#FF375F") }
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

final class AuthStreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let queue = DispatchQueue(label: "com.swingmusic.assetloader")

    private let realURL: URL
    private let headers: [String: String]
    private let fileExtension: String?
    private let session = URLSession(configuration: .default)
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
        let info = loadingRequest.contentInformationRequest != nil ? "info" : "—"
        if let d = loadingRequest.dataRequest {
            Log.debug("stream", "[\(n)] ask data off=\(d.requestedOffset) len=\(d.requestedLength) toEnd=\(d.requestsAllDataToEndOfResource) \(info)")
        } else {
            Log.debug("stream", "[\(n)] ask \(info)-only")
        }
        Task { await handle(loadingRequest, n: n) }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        Log.debug("stream", "request cancelled")
    }

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest, n: Int) async {
        var req = URLRequest(url: realURL)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        var rangeDesc = "none"
        if let dataReq = loadingRequest.dataRequest {
            let start = dataReq.requestedOffset
            if dataReq.requestsAllDataToEndOfResource {
                let r = "bytes=\(start)-"; req.setValue(r, forHTTPHeaderField: "Range"); rangeDesc = r
            } else {
                let end = start + Int64(dataReq.requestedLength) - 1
                let r = "bytes=\(start)-\(end)"; req.setValue(r, forHTTPHeaderField: "Range"); rangeDesc = r
            }
        } else {
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range"); rangeDesc = "bytes=0-1"
        }

        let t0 = Date()
        do {
            let (data, response) = try await session.data(for: req)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard let http = response as? HTTPURLResponse else {
                Log.error("stream", "[\(n)] no HTTP response (range \(rangeDesc))")
                loadingRequest.finishLoading(with: NSError(domain: "AuthStreamLoader", code: 1))
                return
            }
            let ctype = http.value(forHTTPHeaderField: "Content-Type") ?? "—"
            let crange = http.value(forHTTPHeaderField: "Content-Range") ?? "—"
            Log.debug("stream", "[\(n)] → \(http.statusCode) \(data.count)B in \(ms)ms type=\(ctype) range=\(crange)")

            guard (200...299).contains(http.statusCode) else {
                Log.error("stream", "[\(n)] HTTP \(http.statusCode) — failing request")
                loadingRequest.finishLoading(with: NSError(domain: "AuthStreamLoader", code: http.statusCode))
                return
            }

            if let cinfo = loadingRequest.contentInformationRequest {
                let mime = ctype.components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ctype
                if let uti = resolveUTI(mime: mime) {
                    cinfo.contentType = uti
                    Log.debug("stream", "[\(n)] contentType mime=\(mime) ext=\(fileExtension ?? "—") → UTI=\(uti)")
                } else {
                    Log.warn("stream", "[\(n)] no UTI for mime='\(mime)' ext='\(fileExtension ?? "—")' — AVPlayer muss raten")
                }
                cinfo.isByteRangeAccessSupported = true
                if let totalStr = crange.components(separatedBy: "/").last, let total = Int64(totalStr) {
                    cinfo.contentLength = total
                    Log.debug("stream", "[\(n)] contentLength=\(total) (aus Content-Range)")
                } else if let len = http.value(forHTTPHeaderField: "Content-Length"), let total = Int64(len) {
                    cinfo.contentLength = total
                    Log.debug("stream", "[\(n)] contentLength=\(total) (aus Content-Length)")
                } else {
                    Log.warn("stream", "[\(n)] keine Längeninfo (weder Content-Range noch -Length)")
                }
            }

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        } catch {
            Log.error("stream", "[\(n)] URLSession error (range \(rangeDesc)): \(error.localizedDescription)")
            loadingRequest.finishLoading(with: error)
        }
    }
}
