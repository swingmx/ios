import Foundation
import Testing
@testable import Swing_Music_Client

struct AlbumStatsTests {
    // Shaped like POST /album: the stats list is the artist's without the top album, plus completeness.
    private let response = Data("""
    {
      "info": {"albumhash": "al1", "title": "Help!", "image": "al1.webp", "color": "rgb(200, 150, 100)"},
      "tracks": [{"trackhash": "t1", "title": "Help!", "albumhash": "al1"}],
      "stats": [
        {"cssclass": "play_duration", "text": "listened all time", "value": "3 hours"},
        {"cssclass": "played", "text": "never played", "value": "2/14 tracks"},
        {"cssclass": "toptrack", "text": "top track (1 hour listened)", "value": "Help!", "image": "al1.webp"},
        {"cssclass": "completeness", "text": "14/14 tracks available", "value": "100% complete"}
      ]
    }
    """.utf8)

    @Test func albumStatsAreReadInTheServersOrder() throws {
        let detail = try JSONDecoder().decode(AlbumDetail.self, from: response)

        #expect(detail.stats?.map(\.cssclass) == ["play_duration", "played", "toptrack", "completeness"])
        #expect(detail.stats?.last?.value == "100% complete")
        #expect(detail.stats?[2].image == "al1.webp")
    }

    @Test func albumsWithoutStatsStillDecode() throws {
        let json = Data(#"{"info": {"albumhash": "al1", "title": "Help!", "image": "al1.webp"}, "tracks": []}"#.utf8)

        #expect(try JSONDecoder().decode(AlbumDetail.self, from: json).stats == nil)
    }

    @Test func everyStatKindHasItsOwnIcon() {
        let icons = ["play_duration", "played", "toptrack", "topalbum", "completeness"].map(StatsRow.icon)

        #expect(Set(icons).count == icons.count)
        #expect(StatsRow.icon("completeness") == "checkmark.circle.fill")
        #expect(StatsRow.icon("something-new") == "chart.bar.fill")
    }

    // MARK: Favorites and queueing

    @Test func albumAndArtistPagesCarryTheirFavoriteFlag() throws {
        let album = try JSONDecoder().decode(Album.self, from: Data(#"{"albumhash": "al1", "title": "Help!", "image": "al1.webp", "is_favorite": true}"#.utf8))
        let artist = try JSONDecoder().decode(Artist.self, from: Data(#"{"artisthash": "a1", "name": "The Beatles", "image": "a1.webp", "is_favorite": false}"#.utf8))

        #expect(album.isFavorite == true)
        #expect(artist.isFavorite == false)
    }

    @Test func cardsWithoutTheFlagStillDecode() throws {
        let album = try JSONDecoder().decode(Album.self, from: Data(#"{"albumhash": "al1", "title": "Help!", "image": "al1.webp"}"#.utf8))

        #expect(album.isFavorite == nil)
        #expect(Album(stub: "al2", title: "Rubber Soul", image: "", date: nil, albumartists: nil).isFavorite == nil)
    }

    @Test func albumCardMenusQueueTracksInDiscAndTrackOrder() {
        let tracks = [
            Fixtures.track("d2t1", disc: 2, trackno: 1),
            Fixtures.track("d1t2", disc: 1, trackno: 2),
            Fixtures.track("d1t1", disc: 1, trackno: 1),
        ]

        #expect(AlbumMenuItems.albumOrdered(tracks).map(\.trackhash) == ["d1t1", "d1t2", "d2t1"])
    }

    // The album card menu, Home's hero play button and autoplay all fetch tracks this way.
    @Test func albumTracksDecodeFromThePlainArrayTheServerSends() throws {
        let data = Data(#"[{"trackhash": "t1", "title": "Help!"}, {"trackhash": "t2", "title": "The Night Before"}]"#.utf8)

        #expect(try API.decodeAlbumTracks(data).map(\.trackhash) == ["t1", "t2"])
    }

    @Test func albumTracksWrappedInAnObjectStillDecode() throws {
        let data = Data(#"{"tracks": [{"trackhash": "t1", "title": "Help!"}]}"#.utf8)

        #expect(try API.decodeAlbumTracks(data).map(\.trackhash) == ["t1"])
    }
}
