import SwiftUI

struct PlaylistImageGrid: View {
    let playlist: Playlist?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let img = playlist?.customImage {
                Img(url: API.shared.playlistImg(img), radius: size / 8)
            } else if let grid = playlist?.images, !grid.isEmpty {
                // A plain 2×2 layout: a lazy grid costs extra layout in every row and gains nothing at four cells.
                let hashes = (0..<4).map { $0 < grid.count ? grid[$0].image : nil }
                VStack(spacing: 1) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<2, id: \.self) { col in cell(hashes[row * 2 + col]) }
                        }
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    Image(systemName: "music.note.list")
                        .font(.system(size: size / 3))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 8, style: .continuous))
        .zoomSource("playlist-\(playlist?.id ?? "")")
    }

    @ViewBuilder
    private func cell(_ hash: String?) -> some View {
        if let hash {
            // Each cell is a quarter of the cover, so the small thumbnail is plenty.
            Img(urls: ["small", "medium"].compactMap { API.shared.img(hash, size: $0) }, radius: 0)
        } else {
            Color.white.opacity(0.05)
        }
    }
}
