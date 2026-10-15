import Testing
@testable import Swing_Music_Client

struct PreloadTests {
    private let queue = ["a", "b", "c"].map { Fixtures.track($0) }

    @Test func theNextTrackLoadsInTheLast30Seconds() {
        #expect(!AudioPlayer.shouldPreload(time: 169, total: 200, loop: .off))
        #expect(AudioPlayer.shouldPreload(time: 170, total: 200, loop: .off))
        #expect(AudioPlayer.shouldPreload(time: 199, total: 200, loop: .all))
    }

    @Test func tracksShorterThanTheLeadLoadTheNextOneStraightAway() {
        #expect(AudioPlayer.shouldPreload(time: 0, total: 20, loop: .off))
    }

    @Test func nothingLoadsBeforeTheDurationIsKnownOrWhenRepeatingOneTrack() {
        #expect(!AudioPlayer.shouldPreload(time: 0, total: 0, loop: .off))
        #expect(!AudioPlayer.shouldPreload(time: 190, total: 200, loop: .one))
    }

    @Test func thePreparedTrackIsUsedWhenItIsNextInTheQueue() {
        #expect(AudioPlayer.isNextUp(Fixtures.track("b"), queue: queue, index: 0, loop: .off))
        #expect(AudioPlayer.isNextUp(Fixtures.track("c"), queue: queue, index: 1, loop: .all))
    }

    // Covers the queue being reordered or edited after the track was prepared.
    @Test func thePreparedTrackIsNotUsedOnceSomethingElseIsNext() {
        #expect(!AudioPlayer.isNextUp(Fixtures.track("c"), queue: queue, index: 0, loop: .off))
        #expect(!AudioPlayer.isNextUp(Fixtures.track("a"), queue: queue, index: 2, loop: .all))
        #expect(!AudioPlayer.isNextUp(Fixtures.track("b"), queue: queue, index: 0, loop: .one))
    }
}
