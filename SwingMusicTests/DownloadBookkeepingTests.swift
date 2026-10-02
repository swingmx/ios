import Foundation
import Testing
@testable import Swing_Music_Client

struct DownloadBookkeepingTests {
    // MARK: Removing groups

    @Test func removingAGroupKeepsTracksAnotherGroupContains() {
        let album = Fixtures.group("album:al1", .album, ["t1", "t2", "t3"])
        let artist = Fixtures.group("artist:a1", .artist, ["t2", "t4"])

        let deleted = DownloadBookkeeping.tracksToDelete(removing: artist, remaining: [album, artist])

        #expect(deleted == ["t4"])
    }

    @Test func removingTheOnlyGroupDeletesAllItsTracks() {
        let album = Fixtures.group("album:al1", .album, ["t1", "t2"])

        #expect(DownloadBookkeeping.tracksToDelete(removing: album, remaining: [album]) == ["t1", "t2"])
        #expect(DownloadBookkeeping.tracksToDelete(removing: album, remaining: []) == ["t1", "t2"])
    }

    @Test func sharedThumbnailsStayWhileAnyDownloadedTrackUsesThem() {
        let remaining = [Fixtures.track("t2", image: "al1.webp")]

        #expect(DownloadBookkeeping.isImageInUse("al1.webp", by: remaining))
        #expect(!DownloadBookkeeping.isImageInUse("al2.webp", by: remaining))
    }

    @Test func artistImagesStillShownElsewhereAreKept() {
        let a = URL(string: "http://server/img/artist/a1.webp")!
        let b = URL(string: "http://server/img/thumbnail/medium/al1.webp")!

        #expect(DownloadBookkeeping.imagesToRemove([a, b], keeping: [b]) == [a])
    }

    // MARK: Offline images

    @Test func downloadedTracksKeepTheOriginalArtworkForHeadersAndNowPlaying() {
        let paths = DownloadManager.thumbnailURLs(for: Fixtures.track("t1", image: "al1.webp")).map(\.path)

        #expect(paths == ["/img/thumbnail/original/al1.webp", "/img/thumbnail/al1.webp",
                          "/img/thumbnail/medium/al1.webp", "/img/thumbnail/small/al1.webp"])
    }

    // MARK: Ordering

    @Test func albumTracksAreOrderedByDiscThenTrackNumber() {
        let tracks = [
            Fixtures.track("d2t1", disc: 2, trackno: 1),
            Fixtures.track("d1t2", disc: 1, trackno: 2),
            Fixtures.track("d1t1", disc: 1, trackno: 1),
        ]
        let group = Fixtures.group("album:al1", .album, ["d2t1", "d1t2", "d1t1"])

        #expect(DownloadBookkeeping.ordered(tracks, in: group).map(\.trackhash) == ["d1t1", "d1t2", "d2t1"])
    }

    @Test func artistTracksKeepTheSavedOrderAndSkipNonMembers() {
        let tracks = ["t1", "t2", "t3", "other"].map { Fixtures.track($0) }
        let group = Fixtures.group("artist:a1", .artist, ["t3", "t1", "t2"])

        #expect(DownloadBookkeeping.ordered(tracks, in: group).map(\.trackhash) == ["t3", "t1", "t2"])
    }

    @Test func duplicateHashesInAGroupDoNotCrashOrdering() {
        let group = Fixtures.group("playlist:p1", .playlist, ["t1", "t2", "t1"])

        let ordered = DownloadBookkeeping.ordered([Fixtures.track("t2"), Fixtures.track("t1")], in: group)

        #expect(ordered.map(\.trackhash) == ["t1", "t2"])
    }

    // MARK: Resuming after relaunch

    @Test func restoredGroupsKeepTracksStillWaitingToDownload() {
        let artist = Fixtures.group("artist:a1", .artist, ["t1", "t2", "t3"])

        let restored = DownloadBookkeeping.restoredGroups([artist], downloaded: ["t1"], pending: ["t3"])

        #expect(restored.map(\.trackHashes) == [["t1", "t3"]])
    }

    @Test func restoredGroupsDropGroupsWithNothingLeft() {
        let gone = Fixtures.group("album:al9", .album, ["t9"])

        #expect(DownloadBookkeeping.restoredGroups([gone], downloaded: ["t1"], pending: []).isEmpty)
    }

    @Test func resumableKeepsOrderAndSkipsDuplicatesAndFinishedTracks() {
        let pending = ["t1", "t2", "t1", "t3"].map { Fixtures.track($0) }

        let resumed = DownloadBookkeeping.resumable(pending, downloaded: ["t2"])

        #expect(resumed.map(\.trackhash) == ["t1", "t3"])
    }

    // MARK: Saved groups

    @Test func artistGroupsSurviveEncoding() throws {
        let group = Fixtures.group(DownloadManager.artistGroupID("a1"), .artist, ["t1"])

        let decoded = try JSONDecoder().decode(DownloadManager.DownloadGroup.self, from: JSONEncoder().encode(group))

        #expect(decoded == group)
        #expect(decoded.id == "artist:a1")
    }

    @Test func groupsSavedBeforeArtistDownloadsStillDecode() throws {
        let json = Data(#"[{"id":"album:al1","kind":"album","name":"Help!","image":"al1.webp","trackHashes":["t1"]}]"#.utf8)

        let groups = try JSONDecoder().decode([DownloadManager.DownloadGroup].self, from: json)

        #expect(groups.first?.kind == .album)
    }
}
