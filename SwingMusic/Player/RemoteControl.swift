import AVFoundation
import Combine
import Foundation
import MediaPlayer
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
        var playedAt: Double? = nil

        enum CodingKeys: String, CodingKey {
            case uid, playing, loading, at
            case positionMs = "position_ms"
            case playedAt = "played_at"
        }
    }

    struct State: Decodable {
        struct Item: Decodable {
            let uid: String
            let track: Track
        }

        struct Queue: Decodable {
            struct SourceInfo: Decodable { let name: String? }

            let source: String
            let sourceInfo: SourceInfo?
            let items: [Item]
            let order: [String]?
            let `repeat`: String

            enum CodingKeys: String, CodingKey {
                case source, items, order, `repeat`
                case sourceInfo = "source_info"
            }
        }

        let version: Int
        let activeDeviceID: String?
        let activeHostID: String?
        let playhead: Playhead
        let queue: Queue
        let volume: Double
        let devices: [Device]
        let now: Double
        let activeReachable: Bool?
        let playedAt: Double?
        let idleSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case version, playhead, queue, volume, devices, now
            case activeDeviceID = "active_device_id"
            case activeHostID = "active_host_id"
            case activeReachable = "active_reachable"
            case playedAt = "played_at"
            case idleSeconds = "idle_seconds"
        }
    }

    static let enabledKey = "remoteControlEnabled"
    /// When this device last played on its own, so the newest local playback wins on reconnect.
    static let playedAtKey = "remotePlayedAt"

    @Published private(set) var available = false
    @Published private(set) var subscribed = false {
        didSet {
            guard subscribed != oldValue else { return }
            ticker = subscribed
                ? Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
                : nil
        }
    }
    /// True until the first launch check settles, so the Play On button can show a spinner.
    @Published private(set) var checking = true
    @Published private(set) var devices: [Device] = []
    @Published private(set) var activeDeviceID: String?
    @Published private(set) var activeHostID: String?
    @Published var offerPlayHere = false
    /// The active device's volume; on this phone that is the system volume.
    @Published private(set) var volume: Double = 1

    let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "remoteDeviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "remoteDeviceID")
        return id
    }()

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var isActive: Bool { subscribed && activeDeviceID == deviceID }
    /// Only while another reachable device is active and hasn't sat idle; otherwise this device plays locally.
    var isController: Bool {
        subscribed && activeReachable && activeDeviceID != nil && activeDeviceID != deviceID && !idle
    }
    private var idle: Bool {
        idleSeconds > 0 && !playhead.playing && playhead.loading != true
            && Date().timeIntervalSince1970 + clockOffset - (playhead.playedAt ?? 0) > idleSeconds
    }
    var activeDevice: Device? { devices.first { $0.id == activeHostID } }
    private var watched: Bool { devices.contains { $0.id != deviceID } }

    private let player = AudioPlayer.shared
    private let session: URLSession
    private var streamTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var ticker: AnyCancellable?

    private var version = 0
    private var uids: [String] = []
    private var playhead = Playhead(uid: nil, positionMs: 0, playing: false, at: 0) {
        didSet { player.switchingTarget = isController && playhead.loading == true }
    }
    private var activeReachable = false
    private var idleSeconds: Double = 0
    private var pending: [String: Bool] = [:]
    private var heldCatchUp = false
    private var clockOffset: Double = 0
    private var lastReportAt = Date.distantPast
    private var lastReportedPlaying = false

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
            .sink { [weak self] _ in self?.markPlayed() }
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

        SystemVolume.shared.$level.dropFirst()
            .sink { [weak self] v in
                guard let self, isActive, abs(v - volume) > 0.01 else { return }
                setVolume(v)
            }
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
        activeReachable = false
        pending = [:]
        heldCatchUp = false
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
        var delay: UInt64 = 1
        while !Task.isCancelled {
            if !subscribed {
                let ok = await checkAvailable()
                if let ok { available = ok }
                guard ok != false, enabled else { checking = false; return }
            }
            let end = await listen()
            checking = false
            switch end {
            case .fatal:
                endSession()
                available = false
                return
            case .connected:
                delay = 1
            case .failed:
                delay = min(delay * 2, 5)
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
                return [401, 403, 404].contains(code) ? .fatal : .failed
            }
            bytes = b
        } catch {
            Log.warn("remote", "stream failed to open: \(error.localizedDescription)")
            return .failed
        }

        Log.info("remote", "stream open")
        let openedAt = Date()
        subscribed = true
        available = true
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

    /// nil when the server could not be reached, so the check is retried.
    private func checkAvailable() async -> Bool? {
        guard let url = URL(string: API.shared.base + "/remote/state"),
              let (_, resp) = try? await session.data(for: request(url)),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        return code == 200 ? true : [401, 403, 404].contains(code) ? false : nil
    }

    private func catchUp(_ v: Int) async {
        guard pending.isEmpty else { heldCatchUp = true; return }
        guard let url = URL(string: API.shared.base + "/remote/queue?version=\(v)"),
              let (data, resp) = try? await session.data(for: request(url)),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let q = try? JSONDecoder().decode(State.Queue.self, from: data),
              let newVersion = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int
        else { return }
        guard pending.isEmpty else { heldCatchUp = true; return }
        version = newVersion
        renderQueue(q)
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
        let offset = s.now - Date().timeIntervalSince1970
        let playedAt = UserDefaults.standard.double(forKey: Self.playedAtKey)
        // Never over a device that is playing right now, and only against a server that reports `played_at`.
        let newer = playedAt > 0 && !s.playhead.playing && s.playedAt.map { playedAt + offset > $0 } == true
        uids = []
        version = 0
        pending = [:]
        heldCatchUp = false
        idleSeconds = s.idleSeconds ?? 0
        if player.queue.indices.contains(player.index), playingHere || s.queue.items.isEmpty || newer {
            devices = s.devices
            activeDeviceID = deviceID; activeHostID = deviceID
            activeReachable = true
            clockOffset = offset
            updateMode()
            Log.info("remote", "sync: pushing local queue (\(playingHere ? "playing" : newer ? "newer" : "server empty"))")
            await post("/remote/player", ["action": "volume", "value": SystemVolume.shared.value])
            await pushQueue(playedAt: playedAt > 0 ? playedAt + offset : nil)
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
        activeReachable = s.activeReachable ?? false
        idleSeconds = s.idleSeconds ?? 0
        devices = s.devices
        clockOffset = s.now - Date().timeIntervalSince1970
        playhead = s.playhead
        updateMode()
        volume = s.volume
        renderQueue(s.queue)
    }

    private func renderQueue(_ q: State.Queue) {
        let tracks = Dictionary(q.items.map { ($0.uid, $0.track) }, uniquingKeysWith: { a, _ in a })
        let order = (q.order ?? q.items.map(\.uid)).filter { tracks[$0] != nil }
        let local = !player.isController && player.isLoaded
        if order.compactMap({ tracks[$0]?.trackhash }) == player.queue.map(\.trackhash) {
            uids = order
        } else {
            let keptHash = local ? player.current?.trackhash : nil
            uids = order
            player.queue = order.compactMap { tracks[$0] }
            if let keptHash, let i = player.queue.firstIndex(where: { $0.trackhash == keptHash }) {
                player.index = i
            } else if local {
                player.index = min(player.index, max(player.queue.count - 1, 0))
            }
        }
        let source = AudioPlayer.PlaySource(token: q.source)
        if source != player.source || player.sourceName.isEmpty {
            player.source = source
            let name = q.sourceInfo?.name ?? ""
            player.sourceName = name.isEmpty ? AudioPlayer.defaultName(source, in: player.queue) : name
        }
        player.shuffle = q.order != nil
        player.loop = Self.loopMode(q.repeat)

        if local {
            playheadChanged()
        } else {
            showPlayhead()
        }
    }

    private func updateMode() {
        guard isController != player.isController else { return }
        objectWillChange.send()
        player.setController(isController)
        player.switchingTarget = isController && playhead.loading == true
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

    func position() -> Double {
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
            if let dict { await queueEvent(dict) }
        case "playhead":
            guard let p: Playhead = Self.decode(data) else { return }
            playhead = p
            if !isActive, player.isController || !player.isLoaded { showPlayhead() }
        case "devices":
            guard let d: [Device] = Self.decode(data) else { return }
            let was = watched
            devices = d
            if isActive, player.playing, !was, watched { report() }
        case "active":
            let wasActive = isActive
            activeDeviceID = dict?["active_device_id"] as? String
            activeHostID = dict?["active_host_id"] as? String
            activeReachable = dict?["active_reachable"] as? Bool ?? false
            updateMode()
            // playback moved here: this phone plays at its own volume and tells the others
            if isActive, !wasActive { setVolume(SystemVolume.shared.value) }
            if dict?["active_reachable"] as? Bool == false, playhead.playing {
                playhead = Playhead(uid: playhead.uid, positionMs: playhead.positionMs, playing: false,
                                    at: Date().timeIntervalSince1970 + clockOffset)
                if !isActive, player.isController || !player.isLoaded { showPlayhead() }
            }
        case "volume":
            if let v = dict?["value"] as? Double { volume = v }
        case "command":
            if let dict, !player.isController { await execute(dict) }
        case "activate":
            guard let dict, let p: Playhead = Self.decode(dict["playhead"]) else { return }
            await activate(p, play: dict["play"] as? Bool ?? true)
        case "release":
            Log.info("remote", "released: playback moved to another device")
            activeDeviceID = nil; activeHostID = nil
            updateMode()
        default:
            break
        }
    }

    private func queueEvent(_ e: [String: Any]) async {
        guard let v = e["version"] as? Int else { return }
        let base = e["base"] as? Int ?? -1
        let ops = e["ops"] as? [[String: Any]] ?? []
        let resets = (e["batch"] as? String).flatMap { pending.removeValue(forKey: $0) }
        var stale = false
        if e["by"] as? String == deviceID, let resets, resets || base == version {
            version = v
        } else if base != version || ops.contains(where: { $0["type"] as? String == "replace" }) {
            stale = true
        } else if let next = Self.applying(ops, to: uids, player.queue) {
            let currentID = player.isController ? nil : currentUID
            uids = next.uids
            if next.queue.map(\.trackhash) != player.queue.map(\.trackhash) { player.queue = next.queue }
            if let currentID, let i = uids.firstIndex(of: currentID) {
                player.index = i
            } else if !player.isController {
                player.index = min(player.index, max(player.queue.count - 1, 0))
            }
            for op in ops {
                if op["type"] as? String == "order" { player.shuffle = op["shuffled"] as? Bool ?? false }
                if op["type"] as? String == "repeat", let mode = op["mode"] as? String { player.loop = Self.loopMode(mode) }
            }
            version = v
            if player.isController { showPlayhead() }
        } else {
            stale = true
        }
        if stale {
            await catchUp(version)
        } else if pending.isEmpty, let sum = e["sum"] as? Int, UInt32(sum) != Self.orderSum(uids) {
            await catchUp(-1)
        }
        await drained()
    }

    private func drained() async {
        guard pending.isEmpty, heldCatchUp else { return }
        heldCatchUp = false
        await catchUp(-1)
    }

    static func applying(_ ops: [[String: Any]], to uids: [String], _ queue: [Track]) -> (uids: [String], queue: [Track])? {
        var u = uids, q = queue
        func position(after value: Any?) -> Int? {
            guard let after = value as? String else { return 0 }
            return u.firstIndex(of: after).map { $0 + 1 }
        }
        for op in ops {
            switch op["type"] as? String {
            case "insert":
                guard let new = op["uids"] as? [String], let tracks: [Track] = decode(op["tracks"]),
                      tracks.count == new.count, let at = position(after: op["after"]) else { return nil }
                u.insert(contentsOf: new, at: at)
                q.insert(contentsOf: tracks, at: at)
            case "remove":
                let gone = Set(op["uids"] as? [String] ?? [])
                let keep = u.indices.filter { !gone.contains(u[$0]) }
                u = keep.map { u[$0] }
                q = keep.map { q[$0] }
            case "move":
                guard let uid = op["uid"] as? String, let from = u.firstIndex(of: uid) else { return nil }
                u.remove(at: from)
                let t = q.remove(at: from)
                guard let at = position(after: op["after"]) else { return nil }
                u.insert(uid, at: at)
                q.insert(t, at: at)
            case "order":
                let byUID = Dictionary(zip(u, q), uniquingKeysWith: { a, _ in a })
                guard let order = op["uids"] as? [String], order.count == u.count else { return nil }
                let tracks = order.compactMap { byUID[$0] }
                guard tracks.count == order.count else { return nil }
                u = order
                q = tracks
            default:
                break
            }
        }
        return (u, q)
    }

    nonisolated static func orderSum(_ uids: [String]) -> UInt32 {
        var h: UInt32 = 0x811C9DC5
        for b in uids.joined(separator: ",").utf8 { h = (h ^ UInt32(b)) &* 0x01000193 }
        return h
    }

    nonisolated static func newUIDs(_ n: Int) -> [String] {
        (0 ..< n).map { _ in String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)) }
    }

    private static func loopMode(_ mode: String) -> AudioPlayer.LoopMode {
        mode == "all" ? .all : mode == "one" ? .one : .off
    }

    private static func decode<T: Decodable>(_ value: Any?) -> T? {
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
        case "volume":
            if let v = c["value"] as? Double {
                volume = v
                SystemVolume.shared.set(v)
            }
        case "jump":
            guard let uid = c["uid"] as? String else {
                if player.playing { player.toggle() }
                return
            }
            if !uids.contains(uid) { await catchUp(-1) }
            if let i = uids.firstIndex(of: uid) { player.remoteLoad(i, at: 0, play: c["play"] as? Bool ?? true) }
        default:
            break
        }
    }

    private func activate(_ p: Playhead, play: Bool) async {
        activeDeviceID = deviceID; activeHostID = deviceID
        activeReachable = true
        playhead = p
        updateMode()
        setVolume(SystemVolume.shared.value)
        if let uid = p.uid, !uids.contains(uid) { await catchUp(-1) }
        if player.isLoaded, currentUID == p.uid {
            let t = Double(p.positionMs) / 1000
            if abs(player.time - t) > 1 { player.seek(t) }
            if play != player.playing { player.toggle() }
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
        // A device playing while no other is active reports too; the server makes it active.
        guard isActive || player.playing, !player.isController, !player.isStarting,
              currentUID != nil || player.queue.isEmpty else { return }
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
        updateMode()
        if player.isController {
            if playhead.playing { player.time = position() }
        } else if player.playing,
                  watched && Date().timeIntervalSince(lastReportAt) >= 5 || player.isAudible != lastReportedPlaying {
            report()
        }
    }


    // The device playing changed its own queue: it already plays it, so the server just takes a copy.
    private func pushQueue(playedAt: Double? = nil) async {
        uids = Self.newUIDs(player.queue.count)
        var op = replaceOp(take: true)
        if let playedAt { op["played_at"] = playedAt }
        send([op, repeatOp(player.loop)], resets: true)
    }

    private func replaceOp(take: Bool) -> [String: Any] {
        var op: [String: Any] = ["type": "replace", "source": player.source.token, "trackhashes": player.queue.map(\.trackhash),
                                 "uids": uids, "start_index": player.index, "shuffled": player.shuffle]
        if take {
            op["take"] = true
            op["play"] = player.isLoaded && player.playing
            op["position_ms"] = max(0, Int(player.time * 1000))
        } else {
            op["play"] = true
        }
        return op
    }

    func markPlayed() {
        guard !player.isController, player.isLoaded else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.playedAtKey)
    }

    private func send(_ ops: [[String: Any]], resets: Bool = false, tracked: Bool = true) {
        let batch = UUID().uuidString
        if tracked { pending[batch] = resets }
        Task {
            guard await post("/remote/queue", ["ops": ops, "batch": batch]) != nil else { return }
            pending.removeValue(forKey: batch)
            await catchUp(-1)
            await drained()
        }
    }

    func queueReplaced() {
        guard subscribed else { return }
        if player.isController {
            uids = Self.newUIDs(player.queue.count)
            send([replaceOp(take: false)], resets: true)
        } else {
            Task { await pushQueue() }
        }
    }

    func inserted(at i: Int, count: Int) {
        guard subscribed, count > 0, i <= uids.count else { return }
        let new = Self.newUIDs(count)
        uids.insert(contentsOf: new, at: i)
        send([["type": "insert", "trackhashes": player.queue[i ..< i + count].map(\.trackhash), "uids": new,
               "at": ["after": i > 0 ? uids[i - 1] as Any : NSNull()]]])
    }

    func move(from: Int, to: Int) {
        guard subscribed, uids.indices.contains(from) else { return }
        let ops = Self.moveOps(uids: uids, range: 0 ..< uids.count, fromOffsets: [from], toOffset: to)
        uids.move(fromOffsets: [from], toOffset: to)
        if !ops.isEmpty { send(ops) }
    }

    func remove(at i: Int) {
        guard subscribed, uids.indices.contains(i) else { return }
        send([["type": "remove", "uids": [uids.remove(at: i)]]])
    }

    func reordered(from old: [Track]) {
        guard subscribed else { return }
        var pool = [String: [String]]()
        for (t, u) in zip(old, uids) { pool[t.trackhash, default: []].append(u) }
        var order: [String] = []
        for t in player.queue {
            guard let u = pool[t.trackhash]?.first else { return queueReplaced() }
            pool[t.trackhash]?.removeFirst()
            order.append(u)
        }
        uids = order
        send([["type": "order", "uids": order, "shuffled": player.shuffle]])
    }

    func unshuffle() {
        guard subscribed else { return }
        send([["type": "shuffle", "on": false]], tracked: false)
    }

    func repeatChanged() {
        guard subscribed else { return }
        send([repeatOp(player.loop)])
    }

    // offsets are within `range` of the queue
    nonisolated static func moveOps(uids: [String], range: Range<Int>, fromOffsets source: IndexSet,
                                    toOffset destination: Int) -> [[String: Any]] {
        guard !range.isEmpty else { return [] }
        var part = Array(uids[range])
        let moved = source.map { part[$0] }
        part.move(fromOffsets: source, toOffset: destination)
        var order = uids
        order.replaceSubrange(range, with: part)
        return moved.compactMap { uid in
            guard let i = order.firstIndex(of: uid) else { return nil }
            return ["type": "move", "uid": uid, "after": i > 0 ? order[i - 1] : NSNull()]
        }
    }

    private func repeatOp(_ mode: AudioPlayer.LoopMode) -> [String: Any] {
        ["type": "repeat", "mode": mode == .all ? "all" : mode == .one ? "one" : "none"]
    }

    func command(_ action: String, _ args: [String: Any] = [:]) {
        Task {
            switch await post("/remote/player", args.merging(["action": action]) { a, _ in a }) {
            case "no_active_device", "active_unreachable": offerPlayHere = true
            case "unknown_uid": await catchUp(-1)
            default: break
            }
        }
    }

    func jump(to i: Int) {
        guard uids.indices.contains(i) else { return }
        command("jump", ["uid": uids[i]])
    }

    func setVolume(_ value: Double) {
        volume = value
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

// iOS has no API to set the system volume; moving a hidden MPVolumeView's slider is the known workaround.
@MainActor
final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()

    @Published private(set) var level = Double(AVAudioSession.sharedInstance().outputVolume)
    private let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
    private var observation: NSKeyValueObservation?

    var value: Double { Double(AVAudioSession.sharedInstance().outputVolume) }

    // The volume only reads and reports changes while the audio session is active, and the player
    // leaves it inactive until playback so opening the app doesn't stop other apps' audio.
    // shortcut: stays stale while another app plays audio; activating then would stop that app.
    func wake() {
        let session = AVAudioSession.sharedInstance()
        guard !session.isOtherAudioPlaying else { return }
        try? session.setActive(true)
        level = Double(session.outputVolume)
    }

    private init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume) { s, _ in
            let v = Double(s.outputVolume)
            Task { @MainActor in SystemVolume.shared.level = v }
        }
    }

    func set(_ v: Double) {
        attach()
        // A freshly added view only has its slider after a layout pass.
        Task { @MainActor in
            self.view.subviews.compactMap { $0 as? UISlider }.first?.value = Float(min(max(v, 0), 1))
        }
    }

    // In a window, the slider moves the volume without showing the system volume HUD.
    private func attach() {
        guard view.window == nil,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        window.addSubview(view)
    }
}
