import Foundation
import Network

// Plays waiting to be sent to the server, kept on disk so plays made offline or before the app was
// closed still arrive, with the time they actually happened.
@MainActor
final class ScrobbleQueue {
    static let shared = ScrobbleQueue()

    struct Play: Codable, Equatable {
        let trackhash: String
        // Unix seconds when listening ended.
        let timestamp: Int
        // Seconds actually heard.
        let duration: Int
        let source: String
    }

    enum Outcome: Equatable { case sent, dropped, retryLater }

    private var pending: [Play] = []
    private var flushing = false
    private let network = NWPathMonitor()

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending_scrobbles.json")
    }

    private init() {
        load()
        // Send what piled up offline as soon as there is a connection again.
        network.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await ScrobbleQueue.shared.flush() }
        }
        network.start(queue: DispatchQueue(label: "com.swingmusic.scrobble.network"))
    }

    func record(_ play: Play) {
        pending.append(play)
        // Oldest first: the server sets "last played" from whichever play arrives last, and a play
        // recovered from a previous launch can be older than ones already queued.
        pending.sort { $0.timestamp < $1.timestamp }
        save()
        Task { await flush() }
    }

    // Whether a failed send is worth retrying. The server answers 400 for plays it won't accept (under
    // 5 s, no timestamp) and 404 for tracks it doesn't have; those never succeed, and keeping them
    // would block every play queued after them.
    nonisolated static func outcome(of error: Error?) -> Outcome {
        guard let error else { return .sent }
        switch error {
        case APIError.server(let code) where (400..<500).contains(code) && code != 408 && code != 429:
            return .dropped
        case APIError.decode:
            // The server answered with success; only its body was unexpected.
            return .sent
        default:
            return .retryLater
        }
    }

    func flush() async {
        guard !flushing, !pending.isEmpty, API.shared.authed else { return }
        flushing = true
        defer { flushing = false }

        var handled: [Play] = []
        for p in pending {
            var error: Error?
            do { try await API.shared.logPlay(hash: p.trackhash, ts: p.timestamp, dur: p.duration, source: p.source) }
            catch let e { error = e }
            let outcome = Self.outcome(of: error)
            if outcome == .retryLater { break }
            if outcome == .dropped {
                Log.error("scrobble", "Server refused play of \(p.trackhash) (\(error?.localizedDescription ?? "")) — dropped")
            }
            handled.append(p)
        }
        guard !handled.isEmpty else { return }
        // Remove exactly what was handled: plays recorded while sending may have been added in between.
        for p in handled {
            if let i = pending.firstIndex(of: p) { pending.remove(at: i) }
        }
        save()
        Log.info("scrobble", "Flushed \(handled.count) plays, \(pending.count) still pending")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Play].self, from: data) else { return }
        pending = saved
    }
}
