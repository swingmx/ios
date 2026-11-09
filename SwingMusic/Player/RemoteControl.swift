import Combine
import Foundation
import UIKit

@MainActor
final class RemoteControl: ObservableObject {
    static let shared = RemoteControl()

    struct Device: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let type: String
        let selectable: Bool?
    }

    struct Playhead: Decodable {
        let uid: String?
        let positionMs: Int
        let playing: Bool
        var loading: Bool? = nil
        let at: Double

        enum CodingKeys: String, CodingKey {
            case uid, playing, loading, at
            case positionMs = "position_ms"
        }
    }

    struct State: Decodable {
        struct Item: Decodable {
            let uid: String
            let track: Track
        }

        struct Queue: Decodable {
            let source: String
            let items: [Item]
            let order: [String]?
            let `repeat`: String
        }

        let version: Int
        let activeDeviceID: String?
        let activeHostID: String?
        let playhead: Playhead
        let queue: Queue
        let volume: Double
        let devices: [Device]
        let now: Double

        enum CodingKeys: String, CodingKey {
            case version, playhead, queue, volume, devices, now
            case activeDeviceID = "active_device_id"
            case activeHostID = "active_host_id"
        }
    }

    static let enabledKey = "remoteControlEnabled"

    @Published private(set) var available = false
    @Published private(set) var subscribed = false
    /// True until the first launch check settles, so the Play On button can show a spinner.
    @Published private(set) var checking = true
    @Published private(set) var devices: [Device] = []
    @Published private(set) var activeDeviceID: String?
    @Published private(set) var activeHostID: String?
    @Published var offerPlayHere = false

    let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "remoteDeviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "remoteDeviceID")
        return id
    }()

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var isActive: Bool { subscribed && activeDeviceID == deviceID }
    var isController: Bool { subscribed && activeDeviceID != deviceID }
    var activeDevice: Device? { devices.first { $0.id == activeHostID } }

    private let player = AudioPlayer.shared
    private let session: URLSession
    private var streamTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var version = 0
    private var uids: [String] = []
    private var playhead = Playhead(uid: nil, positionMs: 0, playing: false, at: 0) {
        didSet { player.switchingTarget = subscribed && playhead.loading == true }
    }
    private var clockOffset: Double = 0
    private var lastReportAt = Date.distantPast
    private var lastReportedPlaying = false
    private var keepPlayingOnActivate = false

    private var currentUID: String? {
        uids.indices.contains(player.index) ? uids[player.index] : nil
    }

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        session = Net.makeSession(cfg)

        Publishers.Merge(player.$playing.removeDuplicates().map { _ in () },
                         player.$index.removeDuplicates().map { _ in () })
            .sink { [weak self] in self?.playheadChanged() }
            .store(in: &cancellables)

        player.$playing.removeDuplicates()
            .sink { [weak self] playing in
                guard let self, subscribed, UIApplication.shared.applicationState == .background else { return }
                if playing { start() } else { leaveInBackground() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveBeforeExit() }
        }

        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
    }


    func start() {
        guard streamTask == nil, API.shared.authed else {
            if !API.shared.authed { checking = false }
            return
        }
        streamTask = Task { [weak self] in
            await self?.run()
            if !Task.isCancelled { self?.streamTask = nil }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        endSession()
    }

    private func endSession() {
        guard subscribed else { return }
        subscribed = false
        player.switchingTarget = false
        uids = []
        devices = []
        activeDeviceID = nil; activeHostID = nil
        version = 0
        player.leaveRemote()
    }

    func setEnabled(_ on: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    func didEnterBackground() {
        guard !staysConnectedInBackground, streamTask != nil else { return }
        leaveInBackground()
    }

    private var staysConnectedInBackground: Bool { isActive && player.playing }

    private func leaveInBackground() {
        Log.info("remote", "leaving in background")
        let task = streamTask
        streamTask = nil
        let id = UIApplication.shared.beginBackgroundTask()
        Task {
            await post("/remote/leave", [:])
            task?.cancel()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    // Blocks briefly: the process exits as soon as this returns.
    private func leaveBeforeExit() {
        guard subscribed, let url = URL(string: API.shared.base + "/remote/leave") else { return }
        var r = request(url)
        r.httpMethod = "POST"
        r.timeoutInterval = 1
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["device_id": deviceID])
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: r) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 1)
    }

    // A server with Remote Control turned off is checked again when the app comes to the foreground.
    private func run() async {
        if !subscribed {
            available = await fetchState() != nil
            guard available, enabled else { checking = false; return }
        }
        var delay: UInt64 = 1
        while !Task.isCancelled {
            let end = await listen()
            checking = false
            switch end {
            case .fatal:
                endSession()
                available = await fetchState() != nil
                return
            case .connected:
                delay = 1
            case .failed:
                delay = min(delay * 2, 30)
            }
            if UIApplication.shared.applicationState == .background, !staysConnectedInBackground { return }
            Log.info("remote", "reconnecting in \(delay)s")
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
        }
    }

    private enum StreamEnd { case connected, failed, fatal }

    private func listen() async -> StreamEnd {
        var c = URLComponents(string: API.shared.base + "/remote/stream")
        c?.queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "name", value: String(UIDevice.current.name.prefix(100))),
            URLQueryItem(name: "type", value: "ios"),
            URLQueryItem(name: "selectable", value: "true"),
        ]
        guard let url = c?.url else { return .fatal }

        let bytes: URLSession.AsyncBytes
        do {
            let (b, resp) = try await session.bytes(for: request(url))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 {
                Log.error("remote", "stream → \(code)")
                return code >= 500 ? .failed : .fatal
            }
            bytes = b
        } catch {
            Log.warn("remote", "stream failed to open: \(error.localizedDescription)")
            return .failed
        }

        Log.info("remote", "stream open")
        let openedAt = Date()
        subscribed = true
        await sync()
        checking = false
        var reason = "closed by server"
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:"),
                      let obj = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
                      let event = obj["event"] as? String else { continue }
                await handle(event, obj["data"])
            }
        } catch {
            reason = Task.isCancelled ? "cancelled" : error.localizedDescription
        }
        Log.info("remote", "stream ended after \(Int(Date().timeIntervalSince(openedAt)))s: \(reason)")
        return .connected
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        if let t = API.shared.token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func fetchState() async -> State? {
        guard let url = URL(string: API.shared.base + "/remote/state"),
              let (data, resp) = try? await session.data(for: request(url)),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func refresh() async {
        if let s = await fetchState() { apply(s) }
    }

    @discardableResult
    private func post(_ path: String, _ body: [String: Any]) async -> String? {
        guard let url = URL(string: API.shared.base + path) else { return "invalid_url" }
        var body = body
        if path != "/remote/transfer" { body["device_id"] = deviceID }
        var r = request(url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await session.data(for: r),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return "network" }
        guard code >= 400 else { return nil }
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "\(code)"
        Log.error("remote", "POST \(path) → \(code) \(error)")
        return error
    }


    // Playing here, or nothing on the server: this phone's queue wins. Otherwise take the server's.
    private func sync() async {
        guard let s = await fetchState() else { return }
        // A controller's `playing` mirrors the active device and it has no player loaded.
        let playingHere = player.isLoaded && player.playing
        uids = []
        version = 0
        if player.queue.indices.contains(player.index), playingHere || s.queue.items.isEmpty {
            keepPlayingOnActivate = playingHere
            devices = s.devices
            activeDeviceID = playingHere ? deviceID : s.activeDeviceID
            activeHostID = playingHere ? deviceID : s.activeHostID
            Log.info("remote", "sync: pushing local queue (\(playingHere ? "playing" : "server empty"))")
            var op = replaceOp(player.queue, start: player.index, source: player.source, play: playingHere)
            op["take"] = true
            op["position_ms"] = max(0, Int(player.time * 1000))
            await post("/remote/player", ["action": "volume", "value": Double(player.volume)])
            await post("/remote/queue", ["ops": [op, repeatOp(player.loop)]])
            return
        }
        Log.info("remote", "sync: pulling server queue (v\(s.version))")
        apply(s)
        if isActive { await activate(s.playhead, play: false) }
    }

    private func apply(_ s: State) {
        guard s.version >= version else { return }
        version = s.version
        activeDeviceID = s.activeDeviceID
        activeHostID = s.activeHostID
        let keep = isActive && player.isLoaded
        let keptUID = keep ? currentUID : nil
        devices = s.devices
        playhead = s.playhead
        clockOffset = s.now - Date().timeIntervalSince1970
        updateMode()

        let tracks = Dictionary(s.queue.items.map { ($0.uid, $0.track) }, uniquingKeysWith: { a, _ in a })
        uids = (s.queue.order ?? s.queue.items.map(\.uid)).filter { tracks[$0] != nil }
        player.queue = uids.compactMap { tracks[$0] }
        player.source = AudioPlayer.PlaySource(token: s.queue.source)
        player.shuffle = s.queue.order != nil
        player.loop = s.queue.repeat == "all" ? .all : s.queue.repeat == "one" ? .one : .off
        player.volume = Float(s.volume)

        if keep {
            player.index = keptUID.flatMap { uids.firstIndex(of: $0) } ?? min(player.index, max(uids.count - 1, 0))
        } else {
            showPlayhead()
        }
    }

    private func updateMode() {
        if isController != player.isController { player.setController(isController) }
    }

    private func showPlayhead() {
        guard let uid = playhead.uid, let i = uids.firstIndex(of: uid) else {
            if uids.isEmpty { player.current = nil }
            player.playing = false
            return
        }
        player.index = i
        if player.current != player.queue[i] { player.current = player.queue[i] }
        player.total = Double(player.queue[i].duration)
        player.playing = player.isController && playhead.playing
        player.time = position()
    }

    private func position() -> Double {
        var ms = Double(playhead.positionMs)
        if playhead.playing { ms += (Date().timeIntervalSince1970 + clockOffset - playhead.at) * 1000 }
        let t = max(0, ms / 1000)
        return player.total > 0 ? min(t, player.total) : t
    }


    private func handle(_ event: String, _ data: Any?) async {
        let dict = data as? [String: Any]
        switch event {
        case "heartbeat":
            if dict?["ack"] as? Bool != false { await post("/remote/alive", [:]) }
        case "queue":
            if let v = dict?["version"] as? Int, v > version { await refresh() }
        case "playhead":
            guard let p: Playhead = decode(data) else { return }
            playhead = p
            if !isActive { showPlayhead() }
        case "devices":
            if let d: [Device] = decode(data) { devices = d }
        case "active":
            activeDeviceID = dict?["active_device_id"] as? String
            activeHostID = dict?["active_host_id"] as? String
            updateMode()
            if dict?["active_reachable"] as? Bool == false, playhead.playing {
                playhead = Playhead(uid: playhead.uid, positionMs: playhead.positionMs, playing: false,
                                    at: Date().timeIntervalSince1970 + clockOffset)
                if !isActive { showPlayhead() }
            }
        case "volume":
            if let v = dict?["value"] as? Double { player.volume = Float(v) }
        case "command":
            if let dict, !player.isController { await execute(dict) }
        case "activate":
            guard let dict, let p: Playhead = decode(dict["playhead"]) else { return }
            await activate(p, play: dict["play"] as? Bool ?? true)
        case "release":
            Log.info("remote", "released: playback moved to another device")
            activeDeviceID = nil; activeHostID = nil
            updateMode()
        default:
            break
        }
    }

    private func decode<T: Decodable>(_ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func execute(_ c: [String: Any]) async {
        switch c["action"] as? String {
        case "play": if !player.playing { player.toggle() }
        case "pause": if player.playing { player.toggle() }
        case "toggle": player.toggle()
        case "next": player.next()
        case "prev": player.prev()
        case "seek": if let ms = c["position_ms"] as? Double { player.seek(ms / 1000) }
        case "volume": if let v = c["value"] as? Double { player.volume = Float(v) }
        case "jump":
            guard let uid = c["uid"] as? String else {
                if player.playing { player.toggle() }
                return
            }
            if !uids.contains(uid) { await refresh() }
            if let i = uids.firstIndex(of: uid) { player.remoteLoad(i, at: 0, play: c["play"] as? Bool ?? true) }
        default:
            break
        }
    }

    private func activate(_ p: Playhead, play: Bool) async {
        defer { keepPlayingOnActivate = false }
        activeDeviceID = deviceID; activeHostID = deviceID
        playhead = p
        updateMode()
        if let uid = p.uid, !uids.contains(uid) { await refresh() }
        if keepPlayingOnActivate, player.isLoaded, currentUID == p.uid {
            playheadChanged()
            return
        }
        guard let uid = p.uid, let i = uids.firstIndex(of: uid) else { return }
        player.remoteLoad(i, at: Double(p.positionMs) / 1000, play: play)
    }


    func playheadChanged() {
        reportTask?.cancel()
        reportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.report()
        }
    }

    private func report() {
        guard isActive, !player.isController, !player.isStarting else { return }
        lastReportAt = Date()
        lastReportedPlaying = player.playing && player.isAudible
        let body: [String: Any] = [
            "uid": currentUID ?? NSNull(),
            "position_ms": max(0, Int(player.time * 1000)),
            "playing": lastReportedPlaying,
        ]
        Task { await post("/remote/playhead", body) }
    }

    private func tick() {
        guard subscribed else { return }
        if player.isController {
            if playhead.playing { player.time = position() }
        } else if isActive, player.playing,
                  Date().timeIntervalSince(lastReportAt) >= 5 || player.isAudible != lastReportedPlaying {
            report()
        }
    }


    private func replaceOp(_ tracks: [Track], start: Int, source: AudioPlayer.PlaySource, play: Bool) -> [String: Any] {
        ["type": "replace", "source": source.token, "trackhashes": tracks.map(\.trackhash),
         "start_index": start, "play": play]
    }

    private func edit(_ ops: [[String: Any]]) {
        Task {
            if await post("/remote/queue", ["ops": ops]) == "unknown_uid" { await refresh() }
        }
    }

    func replace(_ tracks: [Track], start: Int, source: AudioPlayer.PlaySource, shuffled: Bool = false) {
        var op = replaceOp(tracks, start: start, source: source, play: true)
        op["shuffle"] = shuffled
        edit([op])
    }

    func insert(_ tracks: [Track], next: Bool) {
        guard !tracks.isEmpty else { return }
        edit([["type": "insert", "trackhashes": tracks.map(\.trackhash), "at": next ? "next" : "end"]])
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let ops = Self.moveOps(uids: uids, index: player.index, fromOffsets: source, toOffset: destination)
        if !ops.isEmpty { edit(ops) }
    }

    nonisolated static func moveOps(uids: [String], index: Int, fromOffsets source: IndexSet,
                                    toOffset destination: Int) -> [[String: Any]] {
        let base = index + 1
        guard base < uids.count else { return [] }
        var upcoming = Array(uids[base...])
        let moved = source.map { upcoming[$0] }
        upcoming.move(fromOffsets: source, toOffset: destination)
        let order = Array(uids[..<base]) + upcoming
        return moved.compactMap { uid in
            guard let i = order.firstIndex(of: uid) else { return nil }
            return ["type": "move", "uid": uid, "after": i > 0 ? order[i - 1] : NSNull()]
        }
    }

    func setShuffle(_ on: Bool) {
        edit([["type": "shuffle", "on": on]])
    }

    func setRepeat(_ mode: AudioPlayer.LoopMode) {
        edit([repeatOp(mode)])
    }

    private func repeatOp(_ mode: AudioPlayer.LoopMode) -> [String: Any] {
        ["type": "repeat", "mode": mode == .all ? "all" : mode == .one ? "one" : "none"]
    }

    func command(_ action: String, _ args: [String: Any] = [:]) {
        Task {
            switch await post("/remote/player", args.merging(["action": action]) { a, _ in a }) {
            case "no_active_device", "active_unreachable": offerPlayHere = true
            case "unknown_uid": await refresh()
            default: break
            }
        }
    }

    func jump(to i: Int) {
        guard uids.indices.contains(i) else { return }
        command("jump", ["uid": uids[i]])
    }

    func setVolume(_ value: Double) {
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.command("volume", ["value": value])
        }
    }

    func transfer(to id: String) {
        Task { await post("/remote/transfer", ["device_id": id, "play": true]) }
    }
}
