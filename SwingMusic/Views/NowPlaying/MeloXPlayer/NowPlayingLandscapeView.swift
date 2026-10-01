import SwiftUI

struct NowPlayingLandscapeView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    @Binding var page: NowPlayingPage
    let showsLyricsControls: Bool

    let song: Song
    let lyrics: [MXLyricLine]
    let lyricError: String?
    let highlightedLyricID: MXLyricLine.ID?
    let artworkNamespace: Namespace.ID
    let onDismiss: () -> Void
    let onInterfaceInteraction: () -> Void
    let onInterfaceVisibilityChange: (Bool) -> Void
    let onLyricsContentPrepared: () -> Void

    private var showsSidePane: Bool { page != .artwork }

    private var layoutAnimation: Animation? {
        accessibilityReduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88)
    }

    var body: some View {
        GeometryReader { proxy in
            let W = proxy.size.width
            let H = proxy.size.height
            let margin = W * 0.047
            let top = H * 0.07
            let bottomBarTop = H - 50 - H * 0.035
            let controlsHeight: CGFloat = 262
            let cover = max(200, min(W * 0.38, bottomBarTop - 18 - top - controlsHeight))
            let columnX = showsSidePane ? margin : (W - cover) / 2
            let paneX = W * 0.475
            let paneWidth = W - paneX - margin

            ZStack(alignment: .topLeading) {
                sidePane
                    .frame(width: paneWidth, height: H * 0.86)
                    .offset(x: paneX, y: H * 0.055)
                    .opacity(showsSidePane ? 1 : 0)
                    .offset(x: showsSidePane ? 0 : 40)
                    .allowsHitTesting(showsSidePane)

                playerColumn(cover: cover)
                    .frame(width: cover)
                    .offset(x: columnX, y: top)

                dismissalHandle
                    .frame(width: W)

                bottomBar
                    .frame(width: W - margin * 2, height: 50)
                    .offset(x: margin, y: H - 50 - H * 0.035)
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .animation(layoutAnimation, value: page)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func playerColumn(cover: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkImage(url: song.largeArtworkURL, cornerRadius: 12)
                .frame(width: cover, height: cover)
                .scaleEffect(player.isPlaying || !settings.shrinksPausedArtwork ? 1 : 0.9)
                .shadow(
                    color: .black.opacity(player.isPlaying ? 0.32 : 0.18),
                    radius: player.isPlaying ? 24 : 14,
                    y: player.isPlaying ? 12 : 7
                )
                .animation(.smooth(duration: 0.45), value: player.isPlaying)
                .accessibilityLabel("Cover")

            NowPlayingLandscapeSongHeader(song: song)
                .padding(.top, 22)

            NowPlayingProgressControl(song: song)
                .padding(.top, 10)

            transportRow
                .padding(.top, 14)

            NowPlayingVolumeControl()
                .padding(.top, 18)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(player.isShuffled ? 0.95 : 0.45))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")

            NowPlayingTransportControls()
                .frame(maxWidth: .infinity)

            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(player.repeatMode == .off ? 0.45 : 0.95))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
        }
    }

    @ViewBuilder
    private var sidePane: some View {
        ZStack {
            NowPlayingQueuePage(
                song: song,
                presentation: .landscape,
                artworkNamespace: artworkNamespace,
                usesArtworkTransition: false,
                showsSongHeader: false
            )
            .opacity(page == .queue ? 1 : 0)
            .allowsHitTesting(page == .queue)
            .accessibilityHidden(page != .queue)

            NowPlayingLyricsPage(
                song: song,
                lyrics: lyrics,
                errorMessage: lyricError,
                highlightedLyricID: highlightedLyricID,
                isActive: page == .lyrics,
                presentation: .landscape,
                isInterfaceHidden: false,
                artworkNamespace: artworkNamespace,
                usesArtworkTransition: false,
                showsSongHeader: false,
                onInterfaceInteraction: onInterfaceInteraction,
                onInterfaceVisibilityChange: onInterfaceVisibilityChange,
                onInitialFocusPrepared: onLyricsContentPrepared
            )
            .id(song.id)
            .opacity(page == .lyrics ? 1 : 0)
            .allowsHitTesting(page == .lyrics)
            .accessibilityHidden(page != .lyrics)
        }
    }

    private var dismissalHandle: some View {
        Button(action: onDismiss) {
            Capsule()
                .fill(.white.opacity(0.52))
                .frame(width: 50, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel("Close Player")
    }

    private var bottomBar: some View {
        HStack(spacing: 22) {
            AirPlayButton()
                .frame(width: 44, height: 44)
                .tint(.white.opacity(0.72))

            Spacer()

            pageButton(.lyrics, systemImage: "quote.bubble", label: "Lyrics")
            pageButton(.queue, systemImage: "list.bullet", label: "Queue")
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private func pageButton(_ destination: NowPlayingPage, systemImage: String, label: String) -> some View {
        let isSelected = page == destination
        return Button {
            withAnimation(layoutAnimation) {
                page = isSelected ? .artwork : destination
            }
        } label: {
            Image(systemName: systemImage)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.title3)
                .frame(width: 48, height: 48)
                .foregroundStyle(isSelected ? .black.opacity(0.68) : .white.opacity(0.72))
                .background(.white.opacity(isSelected ? 0.68 : 0), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
