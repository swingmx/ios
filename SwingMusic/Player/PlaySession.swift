import Foundation

// One play of one track, counted the way the web client counts it: only time actually spent playing
// adds up (pauses, stalls and interruptions don't), seeking neither adds nor removes time, and the
// play's timestamp is when listening ended.
struct PlaySession: Codable, Equatable {
    let id: UUID
    let trackhash: String
    let source: String
    // Seconds actually heard.
    private(set) var listened: Double = 0
    // Unix seconds of the last moment counted as heard.
    private(set) var lastHeard: Double?
    // The previous tick while playing; nil while paused, so resuming starts a fresh interval.
    private var lastTick: Double?

    // Ticks further apart than this mean playback wasn't running in between (paused, stalled,
    // suspended), so that stretch isn't counted.
    static let maxGap = 1.5
    // The server rejects plays shorter than this.
    static let minimumListened = 5.0

    init(id: UUID = UUID(), trackhash: String, source: String) {
        self.id = id
        self.trackhash = trackhash
        self.source = source
    }

    mutating func tick(at now: Date, playing: Bool) {
        guard playing else { lastTick = nil; return }
        let t = now.timeIntervalSince1970
        if let prev = lastTick, t > prev, t - prev <= Self.maxGap {
            listened += t - prev
            lastHeard = t
        }
        lastTick = t
    }

    mutating func pause() { lastTick = nil }

    // What to send the server, or nil when too little was heard to count as a play.
    var play: ScrobbleQueue.Play? {
        guard listened >= Self.minimumListened, let lastHeard else { return nil }
        return ScrobbleQueue.Play(trackhash: trackhash, timestamp: Int(lastHeard),
                                  duration: Int(listened.rounded()), source: source)
    }
}
