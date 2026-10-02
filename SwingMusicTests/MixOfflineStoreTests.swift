import Foundation
import Testing
@testable import Swing_Music_Client

struct MixOfflineStoreTests {
    private let store = MixOfflineStore(
        root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    )

    @Test func aSavedMixKeepsEverythingItsPageShows() throws {
        let online = try JSONDecoder().decode(Mix.self, from: Fixtures.trackMixResponse)
        try store.save(online)

        let offline = try #require(store.mix(for: "t1abc"))

        #expect(offline.title == online.title)
        #expect(offline.tagline == "Featuring Dominic Fike, LANY, mxmtoon, Mitski and more")
        #expect(offline.time == online.time)
        #expect(offline.trackcount == 40)
        #expect(offline.sourcehash == online.sourcehash)
        #expect(offline.ogSourcehash == "og1")
        #expect(offline.extra == online.extra)
        #expect(offline.extra.images?.map(\.type) == ["album", "artist", "artist", "artist"])
        #expect(offline.offlineImageURLs == online.offlineImageURLs)
    }

    @Test func artistMixImagesSurviveSaving() throws {
        try store.save(try JSONDecoder().decode(Mix.self, from: Fixtures.artistMixResponse))

        let offline = try #require(store.mix(for: "a1xyz"))

        #expect(offline.extra.image?.image == "lany.webp")
        #expect(offline.extra.image?.color == "rgb(10, 20, 30)")
    }

    @Test func allSavedMixesAreListed() throws {
        try store.save(try JSONDecoder().decode(Mix.self, from: Fixtures.trackMixResponse))
        try store.save(try JSONDecoder().decode(Mix.self, from: Fixtures.artistMixResponse))

        #expect(Set(store.all().map(\.id)) == ["t1abc", "a1xyz"])
    }

    @Test func removingAMixDeletesIt() throws {
        try store.save(try JSONDecoder().decode(Mix.self, from: Fixtures.trackMixResponse))

        store.remove("t1abc")

        #expect(store.mix(for: "t1abc") == nil)
        #expect(store.all().isEmpty)
    }

    @Test func groupIDsGiveBackTheirItemID() {
        let group = Fixtures.group(DownloadManager.mixGroupID("t1abc"), .mix, [])

        #expect(DownloadManager.itemID(of: group) == "t1abc")
        #expect(DownloadManager.itemID(of: Fixtures.group("noprefix", .folder, [])) == "noprefix")
    }
}
