import SwiftUI

struct AlbumCard: View {
    let album: Album
    var size: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumCover(album: album, size: size)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
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

    var body: some View {
        VStack(spacing: 10) {
            ArtistAvatar(artist: artist, size: size)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: size)
        }
    }
}
