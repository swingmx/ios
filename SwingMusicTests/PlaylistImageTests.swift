import Foundation
import Testing
@testable import Swing_Music_Client

struct PlaylistImageTests {
    private func playlist(_ json: String) throws -> Playlist {
        try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
    }

    @Test func customCoversUseThePlaylistImageEndpoint() throws {
        let url = try #require(API.shared.playlistImg("12.webp"))

        #expect(url.path == "/img/playlist/12.webp")
    }

    @Test func anUploadedCoverIsUsed() throws {
        let p = try playlist(#"{"id": 12, "name": "Road trip", "image": "12.webp", "has_image": true}"#)

        #expect(p.customImage == "12.webp")
    }

    @Test func noCoverMeansTheGridIsShown() throws {
        let p = try playlist(#"{"id": 12, "name": "Road trip", "image": "None", "has_image": false}"#)

        #expect(p.customImage == nil)
    }

    @Test func aCoverMissingOnTheServerIsIgnored() throws {
        let p = try playlist(#"{"id": 12, "name": "Road trip", "image": "12.webp", "has_image": false}"#)

        #expect(p.customImage == nil)
    }

    @Test func playlistsSavedBeforeHasImageStillShowTheirCover() throws {
        let p = try playlist(#"{"id": "12", "name": "Road trip", "image": "12.webp"}"#)

        #expect(p.customImage == "12.webp")
    }

    @Test func hasImageSurvivesEncoding() throws {
        let p = try playlist(#"{"id": 12, "name": "Road trip", "image": "12.webp", "has_image": false}"#)

        let decoded = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(p))

        #expect(decoded.hasImage == false)
        #expect(decoded.customImage == nil)
    }
}
