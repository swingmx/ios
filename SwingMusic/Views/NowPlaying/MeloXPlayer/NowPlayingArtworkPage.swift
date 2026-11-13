import SwiftUI

struct NowPlayingArtworkPage: View {
    static let pausedArtworkScale: CGFloat = 0.74

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    let song: Song
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsArtwork: Bool
    let onArtworkFrameChange: (CGRect) -> Void

    @State private var artworkBounceScale: CGFloat = 1

    init(
        song: Song,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsArtwork: Bool = true,
        onArtworkFrameChange:
            @escaping (CGRect) -> Void = { _ in }
    ) {
        self.song = song
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsArtwork = showsArtwork
        self.onArtworkFrameChange = onArtworkFrameChange
    }

    private var isArtworkExpanded: Bool {
        player.isPlaying || !settings.shrinksPausedArtwork
    }

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(
                170,
                min(
                    proxy.size.width + 16,
                    proxy.size.height
                        - NowPlayingBottomControls.coreHeight
                        - 92
                        - NowPlayingSourceHeader.height
                )
            )
            let displayedArtworkSize =
                artworkSize
                * (
                    isArtworkExpanded
                        ? 1
                        : Self.pausedArtworkScale
                )

            VStack(spacing: 0) {
                NowPlayingSourceHeader()

                Spacer(minLength: 8)

                ZStack {
                    if showsArtwork {
                        ArtworkImage(
                            url: song.largeArtworkURL,
                            cornerRadius: 12
                        )
                        .frame(
                            width: displayedArtworkSize,
                            height: displayedArtworkSize
                        )
                        .scaleEffect(artworkBounceScale)
                        .nowPlayingArtworkTransition(
                            id: song.id,
                            in: artworkNamespace,
                            isEnabled: usesArtworkTransition,
                            isSource: true
                        )
                        .shadow(
                            color: .black.opacity(
                                player.isPlaying ? 0.34 : 0.18
                            ),
                            radius: player.isPlaying ? 26 : 14,
                            y: player.isPlaying ? 15 : 8
                        )
                    } else {
                        Color.clear
                            .frame(
                                width: artworkSize,
                                height: artworkSize
                            )
                            .onGeometryChange(
                                for: CGRect.self
                            ) { geometry in
                                geometry.frame(
                                    in: .named(
                                        NowPlayingPortraitCoordinateSpace
                                            .name
                                    )
                                )
                            } action: { newFrame in
                                onArtworkFrameChange(newFrame)
                            }
                    }
                }
                .frame(width: artworkSize, height: artworkSize)
                .animation(
                    accessibilityReduceMotion
                        ? nil
                        : .smooth(duration: 0.48),
                    value: isArtworkExpanded
                )
                .animation(
                    accessibilityReduceMotion
                        ? nil
                        : .easeInOut(duration: 0.3),
                    value: player.isPlaying
                )
                .accessibilityElement()
                .accessibilityLabel("\(song.name) artwork")
                .accessibilityHidden(!showsArtwork)
                .task(id: player.isPlaying) {
                    await animateArtworkBounce(
                        whenPlaying: player.isPlaying
                    )
                }

                // fixed, so extra height goes above the controls instead of between the image and the title
                Color.clear.frame(height: 18)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(song.name)
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                                .layoutPriority(1)

                            HeartModeNowPlayingBadge()
                            ListenTogetherNowPlayingBadge()
                        }

                        NowPlayingArtistLine(song: song) {
                            Text(song.artistText)
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.64))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NowPlayingSongActions(song: song)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, NowPlayingBottomControls.coreHeight)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func animateArtworkBounce(
        whenPlaying isPlaying: Bool
    ) async {
        artworkBounceScale = 1
        guard showsArtwork,
              isPlaying,
              !accessibilityReduceMotion else {
            return
        }

        await Task.yield()
        withAnimation(.easeOut(duration: 0.17)) {
            artworkBounceScale = 1.055
        }

        do {
            try await Task.sleep(for: .milliseconds(170))
        } catch {
            return
        }

        withAnimation(.spring(duration: 0.42, bounce: 0.24)) {
            artworkBounceScale = 1
        }
    }
}

// Where the queue came from, above the artwork; opens it where there is a screen for it.
struct NowPlayingSourceHeader: View {
    static let height: CGFloat = 46

    @Environment(AppState.self) private var state
    @State private var source = AudioPlayer.shared.source
    @State private var name = AudioPlayer.shared.sourceName

    var body: some View {
        Button {
            if let target { state.navigationTarget = target }
        } label: {
            VStack(spacing: 2) {
                Text(source.label)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                    if target != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(target != nil)
        .opacity(name.isEmpty ? 0 : 1)
        .accessibilityElement(children: .combine)
        .onReceive(AudioPlayer.shared.$source) { source = $0 }
        .onReceive(AudioPlayer.shared.$sourceName) { name = $0 }
    }

    private var target: AppState.NavTarget? {
        switch source {
        case .album(let h):
            .album(Album(stub: h, title: name, image: AudioPlayer.shared.current?.albumhash == h
                ? AudioPlayer.shared.current?.image ?? "" : "", date: nil, albumartists: nil))
        case .artist(let h): .artist(Artist(stub: h, name: name))
        case .folder(let p): .folder(Folder(path: p, name: name))
        case .playlist(let id): .playlist(Playlist(stub: id, name: name, image: nil))
        case .mix(let id, let sourcehash): .mix(Mix(stub: id, title: name, image: "", sourcehash: sourcehash))
        default: nil
        }
    }
}
