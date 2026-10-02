import Testing
@testable import Swing_Music_Client

struct FavoritesHeaderTests {
    @Test func taglinesUseTheWebClientsWording() {
        #expect(FavoritesListHeader.tagline(count: 450, singular: "song", plural: "songs") == "You have 450 favorited songs")
        #expect(FavoritesListHeader.tagline(count: 1, singular: "album", plural: "albums") == "You have 1 favorited album")
        #expect(FavoritesListHeader.tagline(count: 0, singular: "artist", plural: "artists") == "You have 0 favorited artists")
    }

    // iPhone 17: 402pt wide leaves 370pt, two 178pt columns, each centering a 150pt card 14pt in.
    @Test func onAnIPhoneTheHeaderStartsWhereTheFirstAlbumArtworkDoes() {
        #expect(FavoritesListHeader.firstAlbumInset(width: 402) == 30)
    }

    @Test func widerScreensFitMoreColumnsAndAdjustTheInset() {
        // 1024pt: six columns of about 153.7pt, so the artwork starts about 17.8pt in.
        let inset = FavoritesListHeader.firstAlbumInset(width: 1024)
        #expect(abs(inset - 17.83) < 0.01)
    }

    @Test func screensTooNarrowForACardUseThePlainMargin() {
        #expect(FavoritesListHeader.firstAlbumInset(width: 0) == 16)
        #expect(FavoritesListHeader.firstAlbumInset(width: 170) == 16)
    }
}
