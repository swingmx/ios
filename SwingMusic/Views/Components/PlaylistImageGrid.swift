import SwiftUI

struct PlaylistImageGrid: View {
    let playlist: Playlist?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let img = playlist?.image, img != "None" {
                Img(url: API.shared.img(img), radius: size / 8)
            } else if let grid = playlist?.images, !grid.isEmpty {
                let items = grid.prefix(4)
                let cols = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

                LazyVGrid(columns: cols, spacing: 1) {
                    ForEach(0..<4, id: \.self) { i in
                        ZStack {
                            if i < items.count, let hash = items[i].image {
                                Img(url: API.shared.img(hash), radius: 0)
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: size / 8, style: .continuous))
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
    }
}
