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
        let ops = RemoteControl.moveOps(uids: ["q1", "q2", "q3", "q4", "q5"], index: 0,
                                        fromOffsets: [0, 1], toOffset: 4)
        #expect(ops.map { $0["uid"] as? String } == ["q2", "q3"])
        #expect(ops.map { $0["after"] as? String } == ["q5", "q2"])
        #expect(ops.allSatisfy { $0["type"] as? String == "move" })
    }

    @Test func gainFollowsDecibelTaper() {
        #expect(AudioPlayer.gain(0) == 0)
        #expect(AudioPlayer.gain(1) == 1)
        #expect(abs(AudioPlayer.gain(0.5) - 0.0562) < 0.001)
    }
}
