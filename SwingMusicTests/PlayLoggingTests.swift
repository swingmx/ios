import Foundation
import Testing
@testable import Swing_Music_Client

struct PlaySessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    // Ticks every 0.5 s from `from` for `seconds`, the way the player's time observer reports progress.
    private func play(_ s: inout PlaySession, from: Double, seconds: Double, playing: Bool = true) {
        var t = from
        while t <= from + seconds + 0.0001 {
            s.tick(at: start.addingTimeInterval(t), playing: playing)
            t += 0.5
        }
    }

    @Test func onlyTimeSpentPlayingCounts() {
        var s = PlaySession(trackhash: "t1", source: "al:a1")
        play(&s, from: 0, seconds: 10)
        play(&s, from: 10.5, seconds: 60, playing: false)  // paused for a minute
        play(&s, from: 71, seconds: 10)

        #expect(abs(s.listened - 20) < 0.01)
    }

    @Test func aGapInTicksIsNotCounted() {
        var s = PlaySession(trackhash: "t1", source: "")
        play(&s, from: 0, seconds: 10)
        play(&s, from: 40, seconds: 10)  // app suspended or stalled for 30 s without a pause

        #expect(abs(s.listened - 20) < 0.01)
    }

    @Test func theTimestampIsWhenListeningEnded() throws {
        var s = PlaySession(trackhash: "t1", source: "pl:3")
        play(&s, from: 0, seconds: 30)
        s.pause()
        play(&s, from: 31, seconds: 5, playing: false)

        let p = try #require(s.play)
        #expect(p.timestamp == 1_000_030)
        #expect(p.duration == 30)
        #expect(p.trackhash == "t1")
        #expect(p.source == "pl:3")
    }

    // The server rejects anything under 5 s with a 400.
    @Test func playsUnderFiveSecondsAreNotSent() {
        var s = PlaySession(trackhash: "t1", source: "")
        play(&s, from: 0, seconds: 4.5)

        #expect(s.play == nil)
    }

    // An in-progress play is saved to disk and recovered after the app is closed.
    @Test func aSavedPlayRestoresWithItsProgress() throws {
        var s = PlaySession(trackhash: "t1", source: "favorite")
        play(&s, from: 0, seconds: 12)

        let restored = try JSONDecoder().decode(PlaySession.self, from: JSONEncoder().encode(s))

        #expect(restored.play == s.play)
        #expect(restored.id == s.id)
    }
}

struct ScrobbleQueueTests {
    @Test func successAndUnexpectedBodiesCountAsSent() {
        #expect(ScrobbleQueue.outcome(of: nil) == .sent)
        #expect(ScrobbleQueue.outcome(of: APIError.decode(CocoaError(.coderInvalidValue))) == .sent)
    }

    // A play the server refuses would otherwise block every play queued after it.
    @Test func playsTheServerRefusesAreDropped() {
        #expect(ScrobbleQueue.outcome(of: APIError.server(400)) == .dropped)
        #expect(ScrobbleQueue.outcome(of: APIError.server(404)) == .dropped)
    }

    @Test func temporaryFailuresAreRetried() {
        #expect(ScrobbleQueue.outcome(of: APIError.network(URLError(.notConnectedToInternet))) == .retryLater)
        #expect(ScrobbleQueue.outcome(of: APIError.unauthorized) == .retryLater)
        #expect(ScrobbleQueue.outcome(of: APIError.server(500)) == .retryLater)
        #expect(ScrobbleQueue.outcome(of: APIError.server(429)) == .retryLater)
    }
}

struct PlaySourceTests {
    private typealias Source = AudioPlayer.PlaySource

    // The source is saved with the queue as its token, so every kind has to read back the same.
    @Test func everySourceReadsBackFromItsToken() {
        let sources: [Source] = [
            .album("a1"), .artist("ar1"), .playlist("12"), .folder("/music/A: B/C.d"),
            .search("re: mix 2.0"), .favorite, .mix(id: "t1.2", sourcehash: "abc123"), .none,
        ]
        for s in sources {
            #expect(Source(token: s.token) == s)
        }
    }

    @Test func unknownTokensMeanNoSource() {
        #expect(Source(token: "") == .none)
        #expect(Source(token: "tr:abc") == .none)
    }

    // Queues saved before the source was added must still load.
    @Test func aQueueSavedWithoutASourceStillLoads() throws {
        let json = #"{"queue": [], "index": 0, "shuffle": false, "baseOrder": [], "time": 12}"#

        let snap = try JSONDecoder().decode(AudioPlayer.QueueSnapshot.self, from: Data(json.utf8))

        #expect(snap.source == nil)
        #expect(snap.time == 12)
    }
}
