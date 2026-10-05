import Foundation
import Testing
@testable import Swing_Music_Client

struct TrackMenuTests {
    private func track(artists: [(String, String)] = [("Adele", "a1")], album: String = "al1",
                       filepath: String = "/music/Adele/25/01.flac") -> Track {
        let json: [String: Any] = [
            "trackhash": "t1", "title": "Hello", "albumhash": album, "filepath": filepath,
            "artists": artists.map { ["name": $0.0, "artisthash": $0.1] },
        ]
        return try! JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private typealias Rules = TrackMenuRules

    @Test func viewAlbumIsHiddenOnlyOnThatAlbumsScreen() {
        #expect(!Rules.showsViewAlbum(track(album: "al1"), in: .album("al1")))
        #expect(Rules.showsViewAlbum(track(album: "al1"), in: .album("al2")))
        #expect(Rules.showsViewAlbum(track(), in: .artist("a1")))
    }

    @Test func aSoloTrackHasNoArtistEntryOnItsArtistsScreen() {
        #expect(Rules.artistEntry(track(), in: .artist("a1")) == .hidden)
    }

    // Every artist is listed, with the screen's own artist shown but inactive.
    @Test func aFeatureListsAllArtistsWithTheCurrentOneInactive() {
        let feature = track(artists: [("Drake", "d1"), ("Rihanna", "r1")])
        let all = [TrackArtist(name: "Drake", artisthash: "d1"), TrackArtist(name: "Rihanna", artisthash: "r1")]

        #expect(Rules.artistEntry(feature, in: .artist("d1")) == .list(all, current: "d1"))
        #expect(Rules.artistEntry(feature, in: .artist("r1")) == .list(all, current: "r1"))
    }

    // On a compilation, a track may not be by the artist whose screen it is shown on.
    @Test func aTrackNotByTheScreensArtistKeepsTheUsualEntry() {
        let solo = track(artists: [("Adele", "a1")])

        #expect(Rules.artistEntry(solo, in: .artist("x9")) == .single(TrackArtist(name: "Adele", artisthash: "a1")))
    }

    @Test func goToFolderIsHiddenOnlyInThatFolder() {
        let t = track(filepath: "/music/Adele/25/01.flac")

        #expect(!Rules.showsGoToFolder(t, in: .folder("/music/Adele/25")))
        #expect(!Rules.showsGoToFolder(t, in: .folder("/music/Adele/25/")))
        #expect(Rules.showsGoToFolder(t, in: .folder("/music/Adele")))
        #expect(Rules.showsGoToFolder(t, in: .folder("/music/Adele/25/Bonus")))
    }

    @Test func withoutAContextTheMenuIsUnchanged() {
        let feature = track(artists: [("Drake", "d1"), ("Rihanna", "r1")])

        #expect(Rules.showsViewAlbum(feature, in: .none))
        #expect(Rules.showsGoToFolder(feature, in: .none))
        #expect(Rules.artistEntry(feature, in: .none) == .list(feature.artists!, current: nil))
        #expect(Rules.artistEntry(track(), in: .none) == .single(TrackArtist(name: "Adele", artisthash: "a1")))
    }
}
