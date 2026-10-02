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
}
