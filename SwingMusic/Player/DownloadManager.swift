import Foundation
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [String: DownloadState] = [:]
    @Published var downloadedTracks: [Track] = []
    @Published var downloadedHashes: Set<String> = []

    enum DownloadState: Equatable {
        case queued
        case downloading(progress: Double)
        case completed
        case failed
    }

    private let fileManager = FileManager.default

    private var downloadsDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("OfflineMusic", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var metadataURL: URL {
        downloadsDir.appendingPathComponent("metadata.json")
    }

    private init() {
        loadMetadata()
    }

    func isDownloaded(_ track: Track) -> Bool {
        downloadedHashes.contains(track.trackhash)
    }

    func isLyricsDownloaded(_ track: Track) -> Bool {
        fileManager.fileExists(atPath: localLyricsURL(for: track).path)
    }

    func localURL(for track: Track) -> URL {
        let ext = (track.filepath as NSString).pathExtension
        let finalExt = ext.isEmpty ? "m4a" : ext
        return downloadsDir.appendingPathComponent("\(track.trackhash).\(finalExt)")
    }

    func localLyricsURL(for track: Track) -> URL {
        downloadsDir.appendingPathComponent("\(track.trackhash).lrc")
    }

    func download(_ track: Track) {
        guard downloads[track.trackhash] == nil || downloads[track.trackhash] == .failed else { return }
        downloads[track.trackhash] = .queued

        Task {
            await performDownload(track)
        }
    }

    func downloadAll(_ tracks: [Track]) {
        for track in tracks {
            download(track)
        }
    }

    func removeDownload(_ track: Track) {
        let file = localURL(for: track)
        try? fileManager.removeItem(at: file)
        downloads.removeValue(forKey: track.trackhash)
        downloadedTracks.removeAll { $0.trackhash == track.trackhash }
        downloadedHashes.remove(track.trackhash)
        saveMetadata()
    }

    func removeAll() {
        for track in downloadedTracks {
            let file = localURL(for: track)
            try? fileManager.removeItem(at: file)
        }
        downloads.removeAll()
        downloadedTracks.removeAll()
        saveMetadata()
    }

    var totalSize: String {
        let bytes = downloadedTracks.reduce(Int64(0)) { total, track in
            let file = localURL(for: track)
            let size = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            return total + size
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func performDownload(_ track: Track) async {
        let urls = API.shared.streamURLs(track.trackhash, filepath: track.filepath)
        guard let url = urls.first else {
            downloads[track.trackhash] = .failed
            return
        }

        var req = URLRequest(url: url)
        if let tk = API.shared.token {
            req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization")
        }

        downloads[track.trackhash] = .downloading(progress: 0)

        do {
            let (localURLTemp, response) = try await URLSession.shared.download(for: req)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                downloads[track.trackhash] = .failed
                return
            }

            let destinationURL = localURL(for: track)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: localURLTemp, to: destinationURL)

            do {
                let response = try await API.shared.lyrics(hash: track.trackhash, path: track.filepath)
                if let content = response.lyrics {
                    let text: String
                    switch content {
                    case .string(let s): text = s
                    case .lines(let l):

                        text = l.map { $0.text }.joined(separator: "\n")
                    }
                    try text.write(to: localLyricsURL(for: track), atomically: true, encoding: .utf8)
                }
            } catch {
                print("Lyrics download failed (optional): \(error)")
            }

            downloads[track.trackhash] = .completed

            if !downloadedTracks.contains(where: { $0.trackhash == track.trackhash }) {
                downloadedTracks.append(track)
                downloadedHashes.insert(track.trackhash)
            }
            saveMetadata()
        } catch {
            print("Download error: \(error)")
            downloads[track.trackhash] = .failed
        }
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(downloadedTracks) else { return }
        try? data.write(to: metadataURL)
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return }

        downloadedTracks = tracks.filter { track in
            let file = localURL(for: track)
            return fileManager.fileExists(atPath: file.path)
        }

        downloadedHashes = Set(downloadedTracks.map { $0.trackhash })

        for track in downloadedTracks {
            downloads[track.trackhash] = .completed
        }
    }
}
