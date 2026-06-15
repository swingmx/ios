import SwiftUI
import WidgetKit

@main
struct SwingMusicWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MusicNowPlayingWidget()
        RecentlyPlayedWidget()
        MusicLiveActivity()
    }
}
