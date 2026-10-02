import SwiftUI

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}
extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

struct ZoomSource: ViewModifier {
    let id: String
    @Environment(\.zoomNamespace) private var ns
    func body(content: Content) -> some View {
        if let ns { content.matchedTransitionSource(id: id, in: ns) }
        else { content }
    }
}
extension View {
    func zoomSource(_ id: String) -> some View { modifier(ZoomSource(id: id)) }
}

struct AlbumCard: View {
    let album: Album
    var size: CGFloat = 150
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumCover(album: album, size: size)
                .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.14), radius: scheme == .dark ? 8 : 5, y: scheme == .dark ? 4 : 2)
                .zoomSource("album-\(album.albumhash)")
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .contextMenu { AlbumMenuItems(album: album) }
    }
}

// What holding an album card offers, wherever the card appears.
struct AlbumMenuItems: View {
    let album: Album

    var body: some View {
        Button { withTracks { AudioPlayer.shared.playAll($0, source: .album(album.albumhash)) } } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button { withTracks { AudioPlayer.shared.playAll($0, shuffled: true, source: .album(album.albumhash)) } } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Divider()
        Button { withTracks { AudioPlayer.shared.addNext($0) } } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { withTracks { AudioPlayer.shared.addLast($0) } } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
    }

    // Cards only carry the album, so its tracks are fetched first, in disc and track order.
    private func withTracks(_ use: @escaping @MainActor ([Track]) -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let hash = album.albumhash
        Task { @MainActor in
            guard let tracks = try? await API.shared.albumTracks(hash), !tracks.isEmpty else { return }
            use(Self.albumOrdered(tracks))
        }
    }

    static func albumOrdered(_ tracks: [Track]) -> [Track] {
        tracks.sorted { a, b in
            let da = a.disc ?? 1, db = b.disc ?? 1
            if da != db { return da < db }
            return (a.trackno ?? 0) < (b.trackno ?? 0)
        }
    }
}

struct ArtistCard: View {
    let artist: Artist
    var size: CGFloat = 110
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            ArtistAvatar(artist: artist, size: size)
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: scheme == .dark ? 6 : 4, y: scheme == .dark ? 3 : 2)
                .zoomSource("artist-\(artist.artisthash)")
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: size)
        }
    }
}
