import Testing
@testable import Swing_Music_Client

struct FavoritesQueueTests {
    private let favorites = ["f1", "f2", "f3", "f4", "f5"].map { Fixtures.track($0) }
    private func hashes(_ tracks: [Track]) -> [String] { tracks.map(\.trackhash) }

    @Test func inOrderTheFullListIsPositionedAtThePlayingTrack() {
        let result = AudioPlayer.expandedQueue(queue: [Fixtures.track("f3")], index: 0, full: favorites, shuffled: false)

        #expect(hashes(result.queue) == ["f1", "f2", "f3", "f4", "f5"])
        #expect(result.index == 2)
    }

    @Test func shuffledThePlayingTrackStaysFirstAndEveryOtherFavoriteFollowsOnce() {
        let result = AudioPlayer.expandedQueue(queue: [Fixtures.track("f3")], index: 0, full: favorites, shuffled: true)

        #expect(result.index == 0)
        #expect(result.queue.first?.trackhash == "f3")
        #expect(hashes(result.queue).sorted() == ["f1", "f2", "f3", "f4", "f5"])
    }

    @Test func tracksQueuedWhileLoadingStayRightAfterThePlayingOne() {
        let queue = [Fixtures.track("f3"), Fixtures.track("x1"), Fixtures.track("f5")]

        let inOrder = AudioPlayer.expandedQueue(queue: queue, index: 0, full: favorites, shuffled: false)
        #expect(hashes(inOrder.queue) == ["f1", "f2", "f3", "x1", "f5", "f4"])
        #expect(inOrder.index == 2)

        let shuffled = AudioPlayer.expandedQueue(queue: queue, index: 0, full: favorites, shuffled: true)
        #expect(hashes(Array(shuffled.queue.prefix(3))) == ["f3", "x1", "f5"])
        #expect(hashes(shuffled.queue).sorted() == ["f1", "f2", "f3", "f4", "f5", "x1"])
    }

    @Test func aPlayingTrackMissingFromTheListIsFollowedByAllOfIt() {
        let result = AudioPlayer.expandedQueue(queue: [Fixtures.track("gone")], index: 0, full: favorites, shuffled: false)

        #expect(hashes(result.queue) == ["gone", "f1", "f2", "f3", "f4", "f5"])
        #expect(result.index == 0)
    }

    @Test func duplicatesInTheListAreQueuedOnce() {
        let full = favorites + [Fixtures.track("f2")]

        let result = AudioPlayer.expandedQueue(queue: [Fixtures.track("f1")], index: 0, full: full, shuffled: true)

        #expect(result.queue.count == 5)
    }
}
