import SwiftUI

enum NowPlayingLyricsPresentation: Equatable {
    case portrait
    case landscape
}

struct NowPlayingLyricsPage: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppSettings.self) private var settings

    let song: Song
    let lyrics: [MXLyricLine]
    let errorMessage: String?
    let highlightedLyricID: MXLyricLine.ID?
    let isActive: Bool
    let presentation: NowPlayingLyricsPresentation
    let isInterfaceHidden: Bool
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsSongHeader: Bool
    let onInterfaceInteraction: (() -> Void)?
    let onInterfaceVisibilityChange: ((Bool) -> Void)?
    let onInitialFocusPrepared: (() -> Void)?

    init(
        song: Song,
        lyrics: [MXLyricLine],
        errorMessage: String?,
        highlightedLyricID: MXLyricLine.ID?,
        isActive: Bool = true,
        presentation: NowPlayingLyricsPresentation = .portrait,
        isInterfaceHidden: Bool = false,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsSongHeader: Bool = true,
        onInterfaceInteraction: (() -> Void)? = nil,
        onInterfaceVisibilityChange: ((Bool) -> Void)? = nil,
        onInitialFocusPrepared: (() -> Void)? = nil
    ) {
        self.song = song
        self.lyrics = lyrics
        self.errorMessage = errorMessage
        self.highlightedLyricID = highlightedLyricID
        self.isActive = isActive
        self.presentation = presentation
        self.isInterfaceHidden = isInterfaceHidden
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsSongHeader = showsSongHeader
        self.onInterfaceInteraction = onInterfaceInteraction
        self.onInterfaceVisibilityChange = onInterfaceVisibilityChange
        self.onInitialFocusPrepared = onInitialFocusPrepared
    }

    var body: some View {
        VStack(spacing: lyricsContentSpacing) {
            if presentation == .portrait, showsSongHeader {
                songHeader
            }

            lyricsStyleContent
                .id(settings.lyricsStyle)
                .transition(.opacity)
        }
        .padding(.top, sharedSongHeaderInset)
        .padding(.bottom, portraitContentBottomInset)
        .animation(
            accessibilityReduceMotion ? nil : .smooth(duration: 0.3),
            value: settings.lyricsStyle
        )
    }

    private var songHeader: some View {
        NowPlayingSongHeader(
            song: song,
            artworkNamespace: artworkNamespace,
            usesReferenceLayout: usesReferencePortraitLayout,
            usesArtworkTransition: usesArtworkTransition
        )
    }

    @ViewBuilder
    private var lyricsStyleContent: some View {
        NativeAMLLLyricsView(
            bottomInset: isInterfaceHidden ? 24 : appleMusicBottomOverlayHeight + 24,
            onReady: onInitialFocusPrepared
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appleMusicBottomOverlayHeight: CGFloat {
        switch presentation {
        case .portrait:
            NowPlayingBottomControls.overlayHeight
        case .landscape:
            50
        }
    }

    private var portraitContentBottomInset: CGFloat {
        guard presentation == .portrait else { return 0 }
        return settings.lyricsStyle == .appleMusic
            ? 12
            : NowPlayingBottomControls.coreHeight
    }

    private var usesReferencePortraitLayout: Bool {
        presentation == .portrait && settings.lyricsStyle == .appleMusic
    }

    private var lyricsContentSpacing: CGFloat {
        guard presentation == .portrait else { return 0 }
        return usesReferencePortraitLayout ? 16 : 18
    }

    private var sharedSongHeaderInset: CGFloat {
        guard presentation == .portrait, !showsSongHeader else {
            return 0
        }
        return NowPlayingSongHeader.referenceHeight
            + lyricsContentSpacing
    }

}
