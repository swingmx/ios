import SwiftUI

struct Img: View {

    static var cache: [String: UIImage] = [:]

    let urls: [URL]
    var radius: CGFloat = 8

    var blurhash: String? = nil
    var placeholderColor: String? = nil

    @State private var img: UIImage?
    @State private var loading = true

    private var primaryKey: String? { urls.first?.absoluteString }

    init(url: URL?, radius: CGFloat = 8, blurhash: String? = nil, placeholderColor: String? = nil) {
        self.urls = [url].compactMap { $0 }
        self.radius = radius
        self.blurhash = blurhash
        self.placeholderColor = placeholderColor
        _img = State(initialValue: url.flatMap { Img.cache[$0.absoluteString] })
    }

    init(urls: [URL], radius: CGFloat = 8, blurhash: String? = nil, placeholderColor: String? = nil) {
        self.urls = urls
        self.radius = radius
        self.blurhash = blurhash
        self.placeholderColor = placeholderColor
        _img = State(initialValue: urls.first.flatMap { Img.cache[$0.absoluteString] })
    }

    var body: some View {
        Color.clear
            .overlay {
                if let img {
                    Image(uiImage: img).resizable().scaledToFill()
                        .transition(.opacity.animation(.easeIn(duration: 0.25)))
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .task(id: primaryKey) { await load() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let bh = blurhash, let blur = BlurHash.image(bh) {
            Image(uiImage: blur).resizable().scaledToFill()
        } else if let c = placeholderColor.flatMap({ Color(rgbString: $0) }) {
            c.opacity(0.55)
        } else {
            Rectangle().fill(.white.opacity(0.06))
                .overlay { if !loading { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.2)) } }
        }
    }

    private func load() async {
        guard let key = primaryKey else { loading = false; return }
        if let cached = Img.cache[key] { img = cached; loading = false; return }
        loading = true

        var token: String? { API.shared.token }
        for url in urls {
            var req = URLRequest(url: url)
            if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else { continue }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
            guard let ui = UIImage(data: data) else { continue }
            Img.cache[key] = ui
            withAnimation { img = ui; loading = false }
            return
        }
        loading = false
    }
}

struct AlbumArt: View {
    let track: Track
    var size: CGFloat = 48
    var body: some View {

        let sizes = size > 200 ? ["original", "", "medium"] : ["medium", "small"]
        Img(urls: sizes.compactMap { API.shared.img(track.image, size: $0) },
            radius: size > 100 ? 12 : 6,
            blurhash: track.blurhash,
            placeholderColor: track.color)
            .frame(width: size, height: size)
    }
}

struct AlbumCover: View {
    let album: Album
    var size: CGFloat = 160
    var body: some View {
        let sizes = size > 200 ? ["original", "", "medium"] : size > 100 ? ["medium", "small"] : ["small", "medium"]
        Img(urls: sizes.compactMap { API.shared.img(album.image, size: $0) },
            radius: size > 100 ? 12 : 8,
            blurhash: album.blurhash,
            placeholderColor: album.color)
            .frame(width: size, height: size)
    }
}

struct ArtistAvatar: View {
    let artist: Artist
    var size: CGFloat = 100
    var body: some View {
        let sizes = size > 100 ? ["", "medium"] : ["medium", "small"]
        Img(urls: sizes.compactMap { API.shared.artistImg(artist.image, size: $0) }, radius: size / 2)
            .frame(width: size, height: size).clipShape(Circle())
    }
}
