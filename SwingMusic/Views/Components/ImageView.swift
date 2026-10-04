import SwiftUI

enum ImageDiskCache {
    private static let browseDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static let offlineDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("OfflineMusic/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func key(for url: URL) -> String {
        let raw = url.path + (url.query.map { "?\($0)" } ?? "")
        var hash: UInt64 = 5381
        for b in raw.utf8 { hash = (hash &* 33) ^ UInt64(b) }
        return String(hash, radix: 16)
    }

    static func image(for url: URL) -> UIImage? {
        let name = key(for: url)
        if let data = try? Data(contentsOf: offlineDir.appendingPathComponent(name)), let ui = UIImage(data: data) { return ui }
        if let data = try? Data(contentsOf: browseDir.appendingPathComponent(name)), let ui = UIImage(data: data) { return ui }
        return nil
    }

    static func storeBrowse(_ data: Data, for url: URL) {
        try? data.write(to: browseDir.appendingPathComponent(key(for: url)), options: .atomic)
    }

    static func storeOffline(_ data: Data, for url: URL) {
        try? data.write(to: offlineDir.appendingPathComponent(key(for: url)), options: .atomic)
    }

    static func hasOffline(for url: URL) -> Bool {
        FileManager.default.fileExists(atPath: offlineDir.appendingPathComponent(key(for: url)).path)
    }

    static func removeOffline(for url: URL) {
        try? FileManager.default.removeItem(at: offlineDir.appendingPathComponent(key(for: url)))
    }
}

// Decoded images by URL. NSCache lets iOS drop them under memory pressure, which the plain
// dictionary used before never did.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let images = NSCache<NSString, UIImage>()

    init() { images.totalCostLimit = 150 * 1024 * 1024 }

    subscript(key: String) -> UIImage? {
        get { images.object(forKey: key as NSString) }
        set {
            if let newValue {
                images.setObject(newValue, forKey: key as NSString, cost: Self.cost(of: newValue))
            } else {
                images.removeObject(forKey: key as NSString)
            }
        }
    }

    // Bytes the decoded bitmap takes.
    static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

// Reading and decoding images off the main thread. UIImage(data:) only decodes when the image is
// first drawn, which happened on the main thread mid-scroll and made lists stutter.
enum ImageDecoding {
    static func decoded(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { UIImage(data: data).map(prepared) }.value
    }

    static func cached(_ urls: [URL]) async -> (exact: UIImage?, preview: UIImage?) {
        await Task.detached(priority: .userInitiated) {
            Img.cachedImage(for: urls,
                            memory: { ImageMemoryCache.shared[$0.absoluteString] },
                            disk: { ImageDiskCache.image(for: $0).map(prepared) })
        }.value
    }

    private static func prepared(_ image: UIImage) -> UIImage { image.preparingForDisplay() ?? image }
}

struct Img: View {
    static var cache: ImageMemoryCache { .shared }

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

    // Images are cached under the URL they came from, so a smaller fallback size is never served
    // when the first (preferred) URL is asked for. A smaller size already on hand is only used when
    // no listed size can be fetched (offline); online the preferred one shows directly, without a
    // visible swap from low to high resolution.
    nonisolated static func cachedImage(for urls: [URL], memory: (URL) -> UIImage?, disk: (URL) -> UIImage?)
        -> (exact: UIImage?, preview: UIImage?) {
        guard let primary = urls.first else { return (nil, nil) }
        if let exact = memory(primary) ?? disk(primary) { return (exact, nil) }
        for url in urls.dropFirst() {
            if let preview = memory(url) ?? disk(url) { return (nil, preview) }
        }
        return (nil, nil)
    }

    private func load() async {
        guard let primaryKey else { loading = false; return }
        if let hit = Img.cache[primaryKey] { img = hit; loading = false; return }
        let cached = await ImageDecoding.cached(urls)
        if let exact = cached.exact {
            Img.cache[urls[0].absoluteString] = exact
            img = exact
            loading = false
            return
        }
        loading = img == nil

        var token: String? { API.shared.token }
        for url in urls {
            var req = URLRequest(url: url)
            if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            guard let (data, resp) = try? await Net.session.data(for: req) else { continue }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
            guard let ui = await ImageDecoding.decoded(data) else { continue }
            Img.cache[url.absoluteString] = ui
            ImageDiskCache.storeBrowse(data, for: url)
            withAnimation { img = ui; loading = false }
            return
        }
        if img == nil, let fallback = cached.preview { img = fallback }
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
        // Headers use the 1200px original, cards the 512px large size (""), list rows the small sizes.
        let sizes = size > 200 ? ["original", "", "medium"] : size > 100 ? ["", "medium"] : ["small", "medium"]
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
