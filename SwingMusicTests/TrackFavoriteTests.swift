import Foundation
import Testing
@testable import Swing_Music_Client

struct TrackFavoriteTests {
    private func track(_ json: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }

    @Test func theServersFavoriteFlagIsRead() throws {
        #expect(try track(#"{"trackhash": "t1", "is_favorite": true}"#).isFavorite == true)
        #expect(try track(#"{"trackhash": "t1", "is_favorite": false}"#).isFavorite == false)
    }

    @Test func tracksWithoutTheFlagAreUnknownRatherThanNotFavorite() throws {
        #expect(try track(#"{"trackhash": "t1"}"#).isFavorite == nil)
    }

    // Downloaded tracks are saved by encoding them, so the flag has to survive a round trip.
    @Test func theFlagSurvivesEncoding() throws {
        let saved = try track(#"{"trackhash": "t1", "is_favorite": true}"#)

        let reloaded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(saved))

        #expect(reloaded.isFavorite == true)
    }
}
