import Foundation
import Testing
@testable import Swing_Music_Client

struct FavoritesHeaderTests {
    @Test func taglinesUseTheWebClientsWording() {
        #expect(FavoritesListHeader.tagline(count: 450, singular: "song", plural: "songs") == "You have 450 favorited songs")
        #expect(FavoritesListHeader.tagline(count: 1, singular: "album", plural: "albums") == "You have 1 favorited album")
        #expect(FavoritesListHeader.tagline(count: 0, singular: "artist", plural: "artists") == "You have 0 favorited artists")
    }

    // iPhone 15 Pro: 393pt wide leaves 345pt inside the 24pt margins: two 150pt album cards 45pt apart.
    @Test func onAnIPhoneAlbumCardsSitOnTheMargins() {
        let layout = FavoritesListHeader.gridLayout(width: 393, card: FavoritesListHeader.albumCard)
        #expect(layout.columns == 2)
        #expect(layout.spacing == 45)
    }

    @Test func artistCardsFitThreeToARowOnAnIPhone() {
        let layout = FavoritesListHeader.gridLayout(width: 393, card: FavoritesListHeader.artistCard)
        #expect(layout.columns == 3)
        #expect(layout.spacing == 16.5)
    }

    // Columns and spacing always add up to the width between the margins.
    @Test func widerScreensFitMoreColumnsEdgeToEdge() {
        let width: CGFloat = 1024, card = FavoritesListHeader.albumCard
        let layout = FavoritesListHeader.gridLayout(width: width, card: card)
        #expect(layout.columns == 6)
        let used = CGFloat(layout.columns) * card + CGFloat(layout.columns - 1) * layout.spacing
        #expect(abs(used - (width - FavoritesListHeader.margin * 2)) < 0.001)
        #expect(layout.spacing >= FavoritesListHeader.gridSpacing)
    }

    @Test func screensTooNarrowForACardUseOneColumn() {
        #expect(FavoritesListHeader.gridLayout(width: 0, card: 150).columns == 1)
        #expect(FavoritesListHeader.gridLayout(width: 170, card: 150).columns == 1)
    }
}
