import Foundation
import Testing
@testable import Swing_Music_Client

// Album and artist screens draw their header from what they were opened with, before the server answers.
struct DetailHeaderTests {
    // A stub built from a track must not carry the track's album art as the artist's portrait.
    @Test func artistStubsUseTheArtistsOwnImage() {
        let a = Artist(stub: "ar1", name: "Adele")

        #expect(a.image == "ar1.webp")
        #expect(a.image == Artist.imageFile(for: "ar1"))
    }

    @Test func theAlbumSubtitleIsTheYearUntilTracksBringTheGenre() throws {
        // 2015-11-20, mid-day UTC so the year is the same in every time zone.
        let album = Album(stub: "al1", title: "25", image: "", date: 1_448_020_800, albumartists: nil)
        let json = #"{"trackhash": "t1", "title": "Hello", "genres": [{"name": "Pop", "genrehash": "g1"}]}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))

        #expect(AlbumDetailView.subtitle(album, tracks: []) == "2015")
        #expect(AlbumDetailView.subtitle(album, tracks: [track]) == "Pop · 2015")
    }
}
