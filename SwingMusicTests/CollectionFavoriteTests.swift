import Foundation
import Testing
@testable import Swing_Music_Client

// The heart on album and artist screens reads AppState, so it agrees with the Favorites tab.
@MainActor
struct CollectionFavoriteTests {
    private let state = AppState()

    private func album(_ hash: String, favorite: Bool?) -> Album {
        var a = Album(stub: hash, title: "A", image: "", date: nil, albumartists: nil)
        a.isFavorite = favorite
        return a
    }

    private func artist(_ hash: String, favorite: Bool?) -> Artist {
        var a = Artist(stub: hash, name: "B", image: "")
        a.isFavorite = favorite
        return a
    }

    @Test func theServersFlagWinsOverTheLoadedFavoritesList() {
        state.favAlbums = [album("al1", favorite: nil)]
        state.favArtists = []

        #expect(!state.isAlbumFavorite(album("al1", favorite: false)))
        #expect(state.isArtistFavorite(artist("ar1", favorite: true)))
    }

    // Offline copies and stubs carry no flag; the favorites list decides.
    @Test func withoutAFlagTheFavoritesListDecides() {
        state.favAlbums = [album("al1", favorite: nil)]
        state.favArtists = [artist("ar1", favorite: nil)]

        #expect(state.isAlbumFavorite(album("al1", favorite: nil)))
        #expect(!state.isAlbumFavorite(album("al2", favorite: nil)))
        #expect(state.isArtistFavorite(artist("ar1", favorite: nil)))
        #expect(!state.isArtistFavorite(artist("ar2", favorite: nil)))
    }
}
