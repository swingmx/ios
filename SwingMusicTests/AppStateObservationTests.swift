import Observation
import SwiftUI
import Testing
@testable import Swing_Music_Client

// AppState is Observable so that views re-render only when something they read changes. Rows reading
// whether their track is playing or a favorite must not re-render when lyrics, colors or the background
// load for a new track: each re-render rebuilds any open menu, which made menus flicker.
@MainActor
struct AppStateObservationTests {
    private let state = AppState()
    private let track = Fixtures.track("t1")

    // Whether `change` notifies a view whose body did `read`.
    private func invalidates(_ read: () -> Void, when change: () -> Void) -> Bool {
        let changed = Flag()
        withObservationTracking(read) { changed.isSet = true }
        change()
        return changed.isSet
    }

    // onChange runs synchronously inside change(), but its closure has to be Sendable.
    private final class Flag: @unchecked Sendable { var isSet = false }

    private func readRow() {
        _ = state.isCurrentTrack(track)
        _ = state.isTrackFavorite(track)
    }

    @Test func theCurrentTrackIsMatchedByHash() {
        state.playingTrackHash = "t1"

        #expect(state.isCurrentTrack(Fixtures.track("t1")))
        #expect(!state.isCurrentTrack(Fixtures.track("t2")))
    }

    @Test func rowsReRenderWhenTheTrackChanges() {
        #expect(invalidates(readRow) { state.playingTrackHash = "t2" })
    }

    @Test func rowsDoNotReRenderWhenANewTracksDetailsLoad() {
        #expect(!invalidates(readRow) {
            state.lyrics = ParsedLyrics(lines: [], synced: false, copyright: nil)
            state.loadingLyrics = true
            state.accent = .red
            state.colorCache["al1"] = .blue
            state.currentBGImage = UIImage()
        })
    }

    @Test func rowsDoNotReRenderForUnrelatedAppState() {
        #expect(!invalidates(readRow) {
            state.keyboardVisible = true
            state.showPlayer = true
            state.tab = .library
            state.homePath.append("x")
        })
    }

    // The lyrics view reacts to lyricsRevision because ParsedLyrics can't be compared.
    @Test func settingLyricsBumpsTheRevision() {
        let before = state.lyricsRevision

        #expect(invalidates({ _ = state.lyricsRevision }) {
            state.lyrics = ParsedLyrics(lines: [], synced: true, copyright: nil)
        })
        #expect(state.lyricsRevision == before + 1)
    }

    // Lyrics are fetched on demand; a request for anything but the playing track must not start a search.
    @Test func lyricsAreNotFetchedForATrackThatIsNotPlaying() {
        guard AudioPlayer.shared.current?.trackhash != track.trackhash else { return }

        state.loadLyrics(for: track)

        #expect(!state.loadingLyrics)
        #expect(state.lyrics == nil)
    }
}
