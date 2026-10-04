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

    // The home feed lists the grid images as plain strings, /playlists as objects. Both have to work,
    // or the grid comes up empty and only the placeholder shows.
    @Test func gridImagesDecodeFromTheHomeFeedAndThePlaylistsList() throws {
        let fromHome = try playlist(#"{"id": 20, "name": "Anime Essentials", "image": "None", "has_image": false, "images": ["a.webp?pathhash=1", "b.webp?pathhash=1"]}"#)
        let fromList = try playlist(#"{"id": 20, "name": "Anime Essentials", "image": "None", "has_image": false, "images": [{"color": "rgb(139, 79, 60)", "image": "a.webp?pathhash=1"}, {"color": "rgb(26, 17, 12)", "image": "b.webp?pathhash=1"}]}"#)

        #expect(fromHome.images?.map(\.image) == ["a.webp?pathhash=1", "b.webp?pathhash=1"])
        #expect(fromList.images == fromHome.images)
    }

    // Playlists are saved for offline use by encoding them, so the decoded images must survive a round trip.
    @Test func gridImagesSurviveEncoding() throws {
        let p = try playlist(#"{"id": 20, "name": "Mix", "images": ["a.webp"]}"#)

        let reloaded = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(p))

        #expect(reloaded.images?.map(\.image) == ["a.webp"])
    }
}
