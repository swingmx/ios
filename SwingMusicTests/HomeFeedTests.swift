import Foundation
import Testing
@testable import Swing_Music_Client

// Items in /nothome/ sections arrive as {"type": ..., "item": {...}}.
struct HomeFeedTests {
    private func decode(_ type: String, _ json: String) -> HomeItem? {
        HomeItem.decode(type: type, json: Data(json.utf8))
    }

    // Recently Played lists your favorites as one item once you have played from them.
    @Test func theFavoritesItemDecodes() throws {
        let item = try #require(decode("favorite", #"{"count": 120, "image": "abc.webp?pathhash=1"}"#))

        #expect(item == .favorites(FavoritesItem(image: "abc.webp?pathhash=1", count: 120)))
        #expect(item.id == "favorites")
    }

    // With no favorited track to take artwork from, the server sends a null image.
    @Test func theFavoritesItemDecodesWithoutArtwork() {
        #expect(decode("favorite", #"{"count": 0, "image": null}"#) == .favorites(FavoritesItem(image: nil, count: 0)))
    }

    @Test func otherKindsStillDecode() {
        #expect(decode("album", #"{"albumhash": "al1", "title": "25", "image": "al1.webp"}"#)?.id == "al:al1")
        #expect(decode("artist", #"{"artisthash": "ar1", "name": "Adele", "image": "ar1.webp"}"#)?.id == "ar:ar1")
    }

    @Test func kindsTheAppDoesNotShowAreSkipped() {
        #expect(decode("folder", #"{"path": "/music", "count": 3}"#) == nil)
    }
}
