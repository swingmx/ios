import Foundation

// Raw server responses behind a downloaded artist's screen, saved as-is so the screen can be
// rebuilt offline with the same decoding it uses online. Kept until the artist download is removed.
struct ArtistOfflineStore {
    static let shared = ArtistOfflineStore(
        root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMusic/Artists", isDirectory: true)
    )

    // The sizes the artist screen's views request. Artists: "" (the largest served, 500px) for the hero
    // and avatar, medium and small for cards. Albums: original for their page's header, large ("") for
    // their cards, medium and small as fallbacks.
    static let artistImageSizes = ["", "medium", "small"]
    static let albumImageSizes = ["original", "", "medium", "small"]

    let root: URL

    private func directory(for hash: String) -> URL {
        root.appendingPathComponent(hash, isDirectory: true)
    }

    func save(artistHash hash: String, detail: Data, tracks: Data) throws {
        let dir = directory(for: hash)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try detail.write(to: dir.appendingPathComponent("artist.json"), options: .atomic)
        try tracks.write(to: dir.appendingPathComponent("tracks.json"), options: .atomic)
    }

    func detail(for hash: String) -> ArtistDetail? {
        guard let data = try? Data(contentsOf: directory(for: hash).appendingPathComponent("artist.json")) else { return nil }
        return try? JSONDecoder().decode(ArtistDetail.self, from: data)
    }

    // Every track the artist had when it was downloaded, most played first.
    func tracks(for hash: String) -> [Track] {
        guard let data = try? Data(contentsOf: directory(for: hash).appendingPathComponent("tracks.json")) else { return [] }
        return (try? JSONDecoder().decode([Track].self, from: data)) ?? []
    }

    func remove(_ hash: String) {
        try? FileManager.default.removeItem(at: directory(for: hash))
    }

    // Every image the artist screen requests: the artist's own, and each album card's cover.
    static func imageURLs(for detail: ArtistDetail, api: API = .shared) -> [URL] {
        var urls = artistImageSizes.compactMap { api.artistImg(detail.artist.image, size: $0) }
        for album in detail.albumSections.flatMap(\.albums) {
            urls += albumImageSizes.compactMap { api.img(album.image, size: $0) }
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
