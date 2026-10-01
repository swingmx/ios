import SwiftUI

struct NowPlayingArtworkTransitionModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    let isEnabled: Bool
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                isSource: isSource
            )
        } else {
            content
        }
    }
}

extension View {
    func nowPlayingArtworkTransition<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        isEnabled: Bool,
        isSource: Bool = true
    ) -> some View {
        modifier(
            NowPlayingArtworkTransitionModifier(
                id: id,
                namespace: namespace,
                isEnabled: isEnabled,
                isSource: isSource
            )
        )
    }
}

struct NowPlayingSongHeader: View {
    static let referenceHeight: CGFloat = 72

    let song: Song
    let artworkNamespace: Namespace.ID
    let usesReferenceLayout: Bool
    let usesArtworkTransition: Bool
    let showsArtwork: Bool

    init(
        song: Song,
        artworkNamespace: Namespace.ID,
        usesReferenceLayout: Bool,
        usesArtworkTransition: Bool = true,
        showsArtwork: Bool = true
    ) {
        self.song = song
        self.artworkNamespace = artworkNamespace
        self.usesReferenceLayout = usesReferenceLayout
        self.usesArtworkTransition = usesArtworkTransition
        self.showsArtwork = showsArtwork
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: artworkSize, height: artworkSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(song.name)
                        .font(
                            usesReferenceLayout
                                ? .title3.weight(.semibold)
                                : .headline
                        )
                        .lineLimit(1)
                        .layoutPriority(1)

                    if song.isExplicit { ExplicitBadge() }
                    HeartModeNowPlayingBadge()
                    ListenTogetherNowPlayingBadge()
                }

                Text(artistText)
                    .font(usesReferenceLayout ? .title3 : .subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NowPlayingSongActions(
                song: song,
                showsFavoriteButton: !usesReferenceLayout
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if showsArtwork {
            ArtworkImage(
                url: song.artworkURL,
                cornerRadius: usesReferenceLayout ? 12 : 10
            )
            .nowPlayingArtworkTransition(
                id: song.id,
                in: artworkNamespace,
                isEnabled: usesArtworkTransition,
                isSource: false
            )
        } else {
            Color.clear
        }
    }

    private var artworkSize: CGFloat {
        usesReferenceLayout ? Self.referenceHeight : 68
    }

    private var artistText: String {
        guard usesReferenceLayout else { return song.artistText }
        return song.allArtists
    }
}

struct NowPlayingLandscapeSongHeader: View {
    let song: Song
    let onExpandLyrics: (() -> Void)?

    init(
        song: Song,
        onExpandLyrics: (() -> Void)? = nil
    ) {
        self.song = song
        self.onExpandLyrics = onExpandLyrics
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(song.name)
                        .font(.headline)
                        .lineLimit(1)
                        .layoutPriority(1)

                    if song.isExplicit { ExplicitBadge() }
                    HeartModeNowPlayingBadge()
                    ListenTogetherNowPlayingBadge()
                }

                Text(song.artistText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onExpandLyrics {
                Button(action: onExpandLyrics) {
                    Image(
                        systemName:
                            "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.title3.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.13), in: .circle)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full-screen lyrics")
            }

            NowPlayingSongActions(song: song)
        }
        .frame(height: 52)
    }
}
