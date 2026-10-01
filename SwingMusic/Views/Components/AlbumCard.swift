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
