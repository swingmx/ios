import Foundation

// Downloaded mixes as they were when downloaded (title, description, type, images and colors), so the
// mix page and its artwork can be rebuilt offline. Its tracks are the mix's download group.
struct MixOfflineStore {
    static let shared = MixOfflineStore(
        root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMusic/Mixes", isDirectory: true)
    )

    let root: URL

    private func file(for id: String) -> URL {
        root.appendingPathComponent("\(id).json")
    }

    func save(_ mix: Mix) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(mix).write(to: file(for: mix.id), options: .atomic)
    }

    func mix(for id: String) -> Mix? {
        guard let data = try? Data(contentsOf: file(for: id)) else { return nil }
        return try? JSONDecoder().decode(Mix.self, from: data)
    }

    func all() -> [Mix] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Mix.self, from: $0) }
        }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(for: id))
    }
}
