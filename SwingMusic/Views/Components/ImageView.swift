import SwiftUI

struct Img: View {

    static var cache: [String: UIImage] = [:]

    let url: URL?
    var radius: CGFloat = 8

    @State private var img: UIImage?
    @State private var loading = true

    init(url: URL?, radius: CGFloat = 8) {
        self.url = url
        self.radius = radius
        _img = State(initialValue: url.flatMap { Img.cache[$0.absoluteString] })
    }

    var body: some View {
        Color.clear
            .overlay {
                if let img {
                    Image(uiImage: img).resizable().scaledToFill()
                        .transition(.opacity.animation(.easeIn(duration: 0.25)))
                } else if loading {
                    Rectangle().fill(.white.opacity(0.06))
                } else {
                    Rectangle().fill(.white.opacity(0.06))
                        .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.2)) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { loading = false; return }
        if let cached = Img.cache[url.absoluteString] { img = cached; loading = false; return }
        loading = true
        var req = URLRequest(url: url)
        if let t = API.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let ui = UIImage(data: data) else { loading = false; return }
        Img.cache[url.absoluteString] = ui
        withAnimation { img = ui; loading = false }
    }
}

struct AlbumArt: View {
    let track: Track
    var size: CGFloat = 48
    var body: some View {
        Img(url: API.shared.img(track.image, size: size > 200 ? "" : "medium"), radius: size > 100 ? 12 : 6)
            .frame(width: size, height: size)
    }
}

struct AlbumCover: View {
    let album: Album
    var size: CGFloat = 160
    var body: some View {
        Img(url: API.shared.img(album.image, size: size > 200 ? "" : size > 100 ? "medium" : "small"), radius: size > 100 ? 12 : 8)
            .frame(width: size, height: size)
    }
}

struct ArtistAvatar: View {
    let artist: Artist
    var size: CGFloat = 100
    var body: some View {
        Img(url: API.shared.artistImg(artist.image, size: size > 100 ? "" : "medium"), radius: size / 2)
            .frame(width: size, height: size).clipShape(Circle())
    }
}
