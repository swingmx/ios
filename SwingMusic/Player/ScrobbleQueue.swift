import Foundation

@MainActor
final class ScrobbleQueue {
    static let shared = ScrobbleQueue()

    private struct PendingPlay: Codable {
        let trackhash: String
        let timestamp: Int
        let duration: Int
        let source: String
    }

    private var pending: [PendingPlay] = []
    private var flushing = false

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending_scrobbles.json")
    }

    private init() { load() }

    func record(trackhash: String, timestamp: Int, duration: Int, source: String) {
        pending.append(PendingPlay(trackhash: trackhash, timestamp: timestamp, duration: duration, source: source))
        save()
        Task { await flush() }
    }

    func flush() async {
        guard !flushing, !pending.isEmpty else { return }
        flushing = true
        defer { flushing = false }

        var remaining = pending
        while let p = remaining.first {
            do {
                try await API.shared.logPlay(hash: p.trackhash, ts: p.timestamp, dur: p.duration, source: p.source)
                remaining.removeFirst()
            } catch {
                break
            }
        }
        if remaining.count != pending.count {
            pending = remaining
            save()
            Log.info("scrobble", "Flushed plays, \(pending.count) still pending")
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([PendingPlay].self, from: data) else { return }
        pending = saved
    }
}
