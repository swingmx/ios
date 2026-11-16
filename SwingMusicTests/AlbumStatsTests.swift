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

    // The album card menu and Home's hero play button fetch tracks this way.
    @Test func albumTracksDecodeFromThePlainArrayTheServerSends() throws {
        let data = Data(#"[{"trackhash": "t1", "title": "Help!"}, {"trackhash": "t2", "title": "The Night Before"}]"#.utf8)

        #expect(try API.decodeAlbumTracks(data).map(\.trackhash) == ["t1", "t2"])
    }

    @Test func albumTracksWrappedInAnObjectStillDecode() throws {
        let data = Data(#"{"tracks": [{"trackhash": "t1", "title": "Help!"}]}"#.utf8)

        #expect(try API.decodeAlbumTracks(data).map(\.trackhash) == ["t1"])
    }
}

// The server takes editions out of album titles and sends them as `versions`.
struct AlbumVersionsTests {
    private func album(_ versions: [String]?) -> Album {
        var a = Album(stub: "h", title: "Rumours", image: "h.webp", date: nil, albumartists: nil)
        a.versions = versions
        return a
    }

    @Test func versionsDecodeAndAreOptional() throws {
        let with = try JSONDecoder().decode(Album.self, from: Data(
            #"{"albumhash": "a", "title": "Rumours", "image": "a.webp", "versions": ["super deluxe", "remaster"]}"#.utf8))
        let without = try JSONDecoder().decode(Album.self, from: Data(
            #"{"albumhash": "a", "title": "Rumours", "image": "a.webp"}"#.utf8))

        #expect(with.versions == ["super deluxe", "remaster"])
        #expect(without.versions == nil)
    }

    // A bad edition card shouldn't stop the album from loading.
    @Test func otherVersionsDecodeAndSkipMalformedOnes() throws {
        let json = #"""
        {"info": {"albumhash": "a", "title": "Rumours", "image": "a.webp"},
         "tracks": [],
         "other_versions": [{"albumhash": "b", "title": "Rumours", "image": "b.webp", "versions": ["deluxe"]},
                            {"title": "no hash"}]}
        """#
        let d = try JSONDecoder().decode(AlbumDetail.self, from: Data(json.utf8))

        #expect(d.otherVersions?.map(\.albumhash) == ["b"])
    }

    @Test func albumsWithoutOtherVersionsStillDecode() throws {
        let json = #"{"info": {"albumhash": "a", "title": "Rumours", "image": "a.webp"}, "tracks": []}"#
        let d = try JSONDecoder().decode(AlbumDetail.self, from: Data(json.utf8))

        #expect(d.otherVersions == nil)
    }

    // Explicit has its own badge by the title.
    @Test func explicitIsNotShownAsAVersion() {
        #expect(AlbumVersions.shown(album(["explicit", "deluxe"])) == ["deluxe"])
        #expect(AlbumVersions.cardLabel(album(["explicit"])) == nil)
        #expect(AlbumVersions.cardLabel(album(nil)) == nil)
    }

    @Test func aCardShowsTheFirstVersion() {
        #expect(AlbumVersions.cardLabel(album(["anniversary", "remaster"])) == "anniversary")
    }

    // Next to the remastered edition, the deluxe remaster reads as DELUXE, not REMASTER again.
    @Test func nextToAnotherEditionACardShowsWhatDiffers() {
        let current = album(["remaster"])

        #expect(AlbumVersions.cardLabel(album(["remaster", "deluxe"]), comparedTo: current) == "deluxe")
        #expect(AlbumVersions.cardLabel(album(["remaster"]), comparedTo: current) == "remaster")
    }
}

// Album cards on an artist's page, as the web client shows them.
struct AlbumCardSubtitleTests {
    // 1 June 2019, midday UTC, so the year is 2019 in any time zone.
    private let date = 1_559_390_400

    private func album(_ artists: [(String, String)], date: Int?) -> Album {
        Album(stub: "h", title: "T", image: "h.webp", date: date,
              albumartists: artists.map { TrackArtist(name: $0.1, artisthash: $0.0) })
    }

    @Test func theArtistsOwnAlbumShowsJustTheYear() {
        #expect(album([("me", "Me")], date: date).cardSubtitle(onArtistPage: "me") == "2019")
    }

    @Test func aSharedAlbumShowsTheYearAndTheOtherArtist() {
        let a = album([("me", "Me"), ("them", "Them"), ("third", "Third")], date: date)
        #expect(a.cardSubtitle(onArtistPage: "me") == "2019 · Them")
    }

    // On Appearances the album artist is someone else.
    @Test func anAppearanceShowsTheAlbumArtist() {
        #expect(album([("them", "Them")], date: date).cardSubtitle(onArtistPage: "me") == "2019 · Them")
    }

    @Test func withoutADateOnlyTheArtistIsShown() {
        #expect(album([("me", "Me"), ("them", "Them")], date: nil).cardSubtitle(onArtistPage: "me") == "Them")
    }

    @Test func elsewhereTheCardShowsTheAlbumArtist() {
        #expect(album([("me", "Me"), ("them", "Them")], date: date).cardSubtitle() == "Me")
    }
}

// "More from" arrives keyed by artist; rows follow the album artists' order.
struct AlbumMoreFromTests {
    @Test func rowsFollowTheAlbumArtistsAndSkipEmptyOnes() throws {
        let json = #"""
        {"info": {"albumhash": "a", "title": "T", "image": "a.webp",
                  "albumartists": [{"name": "First", "artisthash": "one"}, {"name": "Second", "artisthash": "two"},
                                   {"name": "Third", "artisthash": "three"}]},
         "tracks": [],
         "more_from": {"two": [{"albumhash": "b", "title": "B", "image": "b.webp"}, {"title": "broken"}],
                       "one": [{"albumhash": "c", "title": "C", "image": "c.webp"}],
                       "three": []}}
        """#
        let d = try JSONDecoder().decode(AlbumDetail.self, from: Data(json.utf8))

        #expect(d.moreFromSections.map(\.artist.name) == ["First", "Second"])
        #expect(d.moreFromSections.map { $0.albums.map(\.albumhash) } == [["c"], ["b"]])
    }

    @Test func albumsWithoutMoreFromHaveNoRows() throws {
        let json = #"{"info": {"albumhash": "a", "title": "T", "image": "a.webp"}, "tracks": []}"#
        #expect(try JSONDecoder().decode(AlbumDetail.self, from: Data(json.utf8)).moreFromSections.isEmpty)
    }
}
