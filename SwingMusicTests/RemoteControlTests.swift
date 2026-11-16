import Foundation
import Testing
@testable import Swing_Music_Client

struct RemoteControlTests {
    // Shaped like GET /remote/state.
    @Test func decodesState() throws {
        let json = Data("""
        {"version": 3, "active_device_id": "tab1", "active_host_id": "h1", "active_reachable": false,
         "playhead": {"uid": "q2", "position_ms": 1500, "playing": false, "at": 1730881234.1},
         "queue": {"source": "al:ab", "items": [{"uid": "q1", "track": {"trackhash": "t1"}},
                                                {"uid": "q2", "track": {"trackhash": "t2"}}],
                   "order": ["q2", "q1"], "repeat": "all"},
         "volume": 1, "devices": [{"id": "d1", "name": "Chrome on macOS", "type": "web"}], "now": 1730881240.0}
        """.utf8)
        let s = try JSONDecoder().decode(RemoteControl.State.self, from: json)
        #expect(s.activeDeviceID == "tab1")
        #expect(s.activeHostID == "h1")
        #expect(s.playhead.positionMs == 1500)
        #expect(s.queue.order == ["q2", "q1"])
        #expect(s.queue.items.map(\.track.trackhash) == ["t1", "t2"])
        #expect(s.volume == 1)
        #expect(s.devices.first?.name == "Chrome on macOS")
    }
}

extension RemoteControlTests {
    @Test func movesTwoUpcomingItemsToTheEnd() {
        let ops = RemoteControl.moveOps(uids: ["q1", "q2", "q3", "q4", "q5"], range: 1 ..< 5,
                                        fromOffsets: [0, 1], toOffset: 4)
        #expect(ops.map { $0["uid"] as? String } == ["q2", "q3"])
        #expect(ops.map { $0["after"] as? String } == ["q5", "q2"])
        #expect(ops.allSatisfy { $0["type"] as? String == "move" })
    }

    @Test func movesAPreviousItemWithoutPassingTheCurrentOne() {
        let ops = RemoteControl.moveOps(uids: ["p1", "p2", "p3", "cur", "n1"], range: 0 ..< 3,
                                        fromOffsets: [0], toOffset: 3)
        #expect(ops.map { $0["uid"] as? String } == ["p1"])
        #expect(ops.map { $0["after"] as? String } == ["p3"])
    }

    @Test func currentIndexFollowsTracksMovedPastIt() {
        // queue [p0, p1, cur, u3, u4], current at 2
        #expect(PlayerStore.indexAfterMove(current: 2, from: 3, to: 0) == 3)
        #expect(PlayerStore.indexAfterMove(current: 2, from: 3, to: 2) == 3)
        #expect(PlayerStore.indexAfterMove(current: 2, from: 0, to: 4) == 1)
        #expect(PlayerStore.indexAfterMove(current: 2, from: 0, to: 2) == 2)
        #expect(PlayerStore.indexAfterMove(current: 2, from: 4, to: 3) == 2)
    }

    @Test func gainFollowsDecibelTaper() {
        #expect(AudioPlayer.gain(0) == 0)
        #expect(AudioPlayer.gain(1) == 1)
        #expect(abs(AudioPlayer.gain(0.5) - 0.0562) < 0.001)
    }
}

@MainActor
struct RemoteQueueOpsTests {
    let queue = ["a", "b", "c", "d"].map { Fixtures.track($0) }
    let uids = ["u1", "u2", "u3", "u4"]

    @Test func checksumMatchesTheServer() {
        #expect(RemoteControl.orderSum(["q1", "ab3f9c", "x"]) == 201217107)
        #expect(RemoteControl.orderSum([]) == 2166136261)
    }

    @Test func appliesInsertRemoveAndMove() throws {
        let ops: [[String: Any]] = [
            ["type": "insert", "uids": ["n1"], "tracks": [["trackhash": "x"]], "after": "u2"],
            ["type": "remove", "uids": ["u3"]],
            ["type": "move", "uid": "u1", "after": "u4"],
            ["type": "insert", "uids": ["n2"], "tracks": [["trackhash": "y"]], "after": NSNull()],
        ]
        let r = try #require(RemoteControl.applying(ops, to: uids, queue))
        #expect(r.uids == ["n2", "u2", "n1", "u4", "u1"])
        #expect(r.queue.map(\.trackhash) == ["y", "b", "x", "d", "a"])
    }

    @Test func appliesAnOrder() throws {
        let r = try #require(RemoteControl.applying([["type": "order", "uids": ["u4", "u1", "u3", "u2"], "shuffled": true]],
                                                    to: uids, queue))
        #expect(r.queue.map(\.trackhash) == ["d", "a", "c", "b"])
    }

    @Test func unknownUidsFailSoTheQueueIsFetched() {
        #expect(RemoteControl.applying([["type": "move", "uid": "zz", "after": NSNull()]], to: uids, queue) == nil)
        #expect(RemoteControl.applying([["type": "order", "uids": ["u1"], "shuffled": true]], to: uids, queue) == nil)
    }
}
