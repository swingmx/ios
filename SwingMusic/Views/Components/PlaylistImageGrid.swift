import SwiftUI

struct PlaylistImageGrid: View {
    let playlist: Playlist?
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale

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
            let sizes = Self.thumbnailSizes(forCell: size / 2, scale: displayScale)
            Img(urls: sizes.compactMap { API.shared.img(hash, size: $0) }, radius: 0)
        } else {
            Color.white.opacity(0.05)
        }
    }
}

extension PlaylistImageGrid {
    // The server's thumbnail sizes, smallest first: "small" is 96 px, "medium" 256 px and "" (large) 512 px.
    // Picks the smallest that is at least as sharp as the cell, then a fallback.
    nonisolated static func thumbnailSizes(forCell points: CGFloat, scale: CGFloat) -> [String] {
        let pixels = points * scale
        if pixels <= 96 { return ["small", "medium"] }
        if pixels <= 256 { return ["medium", ""] }
        return ["", "medium"]
    }
}
