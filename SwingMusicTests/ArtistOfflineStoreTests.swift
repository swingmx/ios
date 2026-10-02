import Foundation
import Testing
@testable import Swing_Music_Client

struct ArtistOfflineStoreTests {
    private let store = ArtistOfflineStore(
        root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    )

    @Test func savedArtistRebuildsTheSameScreenData() throws {
        try store.save(artistHash: "a1", detail: Fixtures.artistResponse, tracks: Fixtures.artistTracksResponse)

        let detail = try #require(store.detail(for: "a1"))

        #expect(detail.artist.name == "The Beatles")
        #expect(detail.tracks.map(\.trackhash) == ["t2", "t1"])
        #expect(detail.stats?.first?.value == "12")
        #expect(detail.albumSections.map(\.title) == ["Albums", "Singles & EPs", "Compilations"])
        #expect(detail.albumSections.first?.albums.first?.albumhash == "al1")
    }

    @Test func savedOfflineDetailMatchesTheOnlineDecoding() throws {
        try store.save(artistHash: "a1", detail: Fixtures.artistResponse, tracks: Fixtures.artistTracksResponse)
        let online = try JSONDecoder().decode(ArtistDetail.self, from: Fixtures.artistResponse)

        let offline = try #require(store.detail(for: "a1"))

        #expect(offline.tracks == online.tracks)
        #expect(offline.albumSections == online.albumSections)
    }

    @Test func savedTracksKeepTheServersOrder() throws {
        try store.save(artistHash: "a1", detail: Fixtures.artistResponse, tracks: Fixtures.artistTracksResponse)

        #expect(store.tracks(for: "a1").map(\.trackhash) == ["t2", "t1", "t3"])
    }

    @Test func artistsThatWereNeverSavedHaveNothing() {
        #expect(store.detail(for: "missing") == nil)
        #expect(store.tracks(for: "missing").isEmpty)
    }

    @Test func removingAnArtistDeletesItsSavedData() throws {
        try store.save(artistHash: "a1", detail: Fixtures.artistResponse, tracks: Fixtures.artistTracksResponse)

        store.remove("a1")

        #expect(store.detail(for: "a1") == nil)
        #expect(store.tracks(for: "a1").isEmpty)
    }

    @Test func imageURLsCoverTheArtistAndEveryAlbumCardOnce() throws {
        let detail = try JSONDecoder().decode(ArtistDetail.self, from: Fixtures.artistResponse)

        let paths = ArtistOfflineStore.imageURLs(for: detail).map(\.path)

        let expected = [
            "/img/artist/a1.webp", "/img/artist/medium/a1.webp", "/img/artist/small/a1.webp",
            "/img/thumbnail/original/al1.webp", "/img/thumbnail/al1.webp", "/img/thumbnail/medium/al1.webp", "/img/thumbnail/small/al1.webp",
            "/img/thumbnail/original/al2.webp", "/img/thumbnail/al2.webp", "/img/thumbnail/medium/al2.webp", "/img/thumbnail/small/al2.webp",
        ]
        #expect(paths == expected)
    }
}
