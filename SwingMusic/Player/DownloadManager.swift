import Foundation
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [String: DownloadState] = [:]
    @Published var downloadedTracks: [Track] = []
    @Published var downloadedHashes: Set<String> = []
    @Published var downloadGroups: [DownloadGroup] = []

    struct DownloadGroup: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case album, playlist, folder, mix }
        let id: String
        let kind: Kind
        let name: String
        let image: String
        var trackHashes: [String]
    }

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

    private var groupsURL: URL {
        downloadsDir.appendingPathComponent("groups.json")
    }

    private init() {
        loadMetadata()
        loadGroups()
    }

    var ungroupedTracks: [Track] {
        let grouped = Set(downloadGroups.flatMap { $0.trackHashes })
        return downloadedTracks.filter { !grouped.contains($0.trackhash) }
    }

    func tracks(in group: DownloadGroup) -> [Track] {
        let items = downloadedTracks.filter { group.trackHashes.contains($0.trackhash) }
        switch group.kind {
        case .album:
            return items.sorted {
                let d0 = $0.disc ?? 1, d1 = $1.disc ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.trackno ?? 0) < ($1.trackno ?? 0)
            }
        case .folder, .playlist, .mix:
            let order = Dictionary(uniqueKeysWithValues: group.trackHashes.enumerated().map { ($1, $0) })
            return items.sorted { (order[$0.trackhash] ?? 0) < (order[$1.trackhash] ?? 0) }
        }
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

    static func lrcTimestamp(_ seconds: Double) -> String {
        let t = max(0, seconds)
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "[%02d:%02d.%02d]", m, s, cs)
    }

    private let maxConcurrent = 3
    private var pendingQueue: [Track] = []
    private var activeCount = 0

    func download(_ track: Track) {
        guard downloads[track.trackhash] == nil || downloads[track.trackhash] == .failed else { return }
        downloads[track.trackhash] = .queued
        pendingQueue.append(track)
        pumpQueue()
    }

    private func pumpQueue() {
        while activeCount < maxConcurrent, !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            guard downloads[track.trackhash] == .queued else { continue }
            activeCount += 1
            Task {
                await performDownload(track)
                activeCount -= 1
                pumpQueue()
            }
        }
    }

    func downloadAll(_ tracks: [Track], group: DownloadGroup? = nil) {
        if let group {
            if let idx = downloadGroups.firstIndex(where: { $0.id == group.id }) {
                downloadGroups[idx] = group
            } else {
                downloadGroups.append(group)
            }
            saveGroups()
        }
        for track in tracks {
            download(track)
        }
    }

    func removeGroup(_ group: DownloadGroup) {
        for hash in group.trackHashes {
            if let t = downloadedTracks.first(where: { $0.trackhash == hash }) {
                removeDownload(t)
            }
        }
        downloadGroups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func removeDownload(_ track: Track) {
        pendingQueue.removeAll { $0.trackhash == track.trackhash }
        let file = localURL(for: track)
        try? fileManager.removeItem(at: file)
        removeThumbnails(for: track)
        downloads.removeValue(forKey: track.trackhash)
        downloadedTracks.removeAll { $0.trackhash == track.trackhash }
        downloadedHashes.remove(track.trackhash)
        saveMetadata()
    }

    func removeAll() {
        pendingQueue.removeAll()
        for track in downloadedTracks {
            let file = localURL(for: track)
            try? fileManager.removeItem(at: file)
        }
        downloads.removeAll()
        downloadedTracks.removeAll()
        downloadGroups.removeAll()
        saveMetadata()
        saveGroups()
    }

    @Published private(set) var totalSize: String = "–"

    private func refreshTotalSize() {
        let files = downloadedTracks.map { localURL(for: $0).path }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let bytes = files.reduce(Int64(0)) { total, path in
                total + ((try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0)
            }
            let text = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            await MainActor.run { [weak self] in self?.totalSize = text }
        }
    }

    private func performDownload(_ track: Track) async {
        let urls = API.shared.streamURLs(track.trackhash, filepath: track.filepath)
        guard let url = urls.first else {
            Log.error("download", "No stream URL for \(track.title)")
            downloads[track.trackhash] = .failed
            return
        }
        Log.info("download", "Starting \(track.title)")

        var req = URLRequest(url: url)
        if let tk = API.shared.token {
            req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization")
        }

        downloads[track.trackhash] = .downloading(progress: 0)

        do {
            let hash = track.trackhash
            let br = Double(track.bitrate ?? 0)
            let bps = br > 100_000 ? br : (br > 0 ? br * 1000 : 320_000)
            let estimatedBytes = Int64(bps / 8 * Double(max(track.duration, 1)))
            let reporter = DownloadProgressReporter(estimatedTotalBytes: estimatedBytes) { [weak self] p in
                Task { @MainActor in
                    if case .downloading = self?.downloads[hash] {
                        self?.downloads[hash] = .downloading(progress: p)
                    }
                }
            }
            let (localURLTemp, response) = try await downloadFile(req, reporter: reporter)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                try? fileManager.removeItem(at: localURLTemp)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.error("download", "Audio failed for \(track.title) → HTTP \(code)")
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
                    case .string(let s):
                        text = s
                    case .lines(let l):
                        text = l.map { Self.lrcTimestamp($0.time) + $0.text }.joined(separator: "\n")
                    }
                    try text.write(to: localLyricsURL(for: track), atomically: true, encoding: .utf8)
                }
            } catch {
                Log.warn("download", "Lyrics unavailable for \(track.title): \(error.localizedDescription)")
            }

            await cacheThumbnails(for: track)

            downloads[track.trackhash] = .completed
            Log.info("download", "Completed \(track.title)")

            if !downloadedTracks.contains(where: { $0.trackhash == track.trackhash }) {
                downloadedTracks.append(track)
                downloadedHashes.insert(track.trackhash)
            }
            saveMetadata()
        } catch {
            Log.error("download", "Failed \(track.title): \(error.localizedDescription)")
            downloads[track.trackhash] = .failed
        }
    }

    // URLSession's async download(for:delegate:) never calls didWriteData on the task delegate,
    // so progress is read from the task's byte counters instead.
    private nonisolated func downloadFile(_ request: URLRequest, reporter: DownloadProgressReporter) async throws -> (URL, URLResponse) {
        final class ObservationBox: @unchecked Sendable { var observation: NSKeyValueObservation? }
        let box = ObservationBox()
        return try await withCheckedThrowingContinuation { continuation in
            let task = Net.session.downloadTask(with: request) { url, response, error in
                box.observation?.invalidate()
                if let error { continuation.resume(throwing: error); return }
                guard let url, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                // The system deletes `url` as soon as this handler returns.
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: url, to: kept)
                    continuation.resume(returning: (kept, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            box.observation = task.observe(\.countOfBytesReceived) { task, _ in
                reporter.report(written: task.countOfBytesReceived, expected: task.countOfBytesExpectedToReceive)
            }
            task.resume()
        }
    }

    private func cacheThumbnails(for track: Track) async {
        for size in ["small", "medium"] {
            guard let url = API.shared.img(track.image, size: size) else { continue }
            var req = URLRequest(url: url)
            if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
            guard let (data, resp) = try? await Net.session.data(for: req),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
            ImageDiskCache.storeOffline(data, for: url)
        }
    }

    private func removeThumbnails(for track: Track) {
        for size in ["small", "medium"] {
            if let url = API.shared.img(track.image, size: size) { ImageDiskCache.removeOffline(for: url) }
        }
    }

    private var metadataSaveScheduled = false

    private func saveMetadata() {
        guard !metadataSaveScheduled else { return }
        metadataSaveScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            metadataSaveScheduled = false
            refreshTotalSize()
            guard let data = try? JSONEncoder().encode(downloadedTracks) else { return }
            let url = metadataURL
            Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
        }
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
        refreshTotalSize()
    }

    private func saveGroups() {
        guard let data = try? JSONEncoder().encode(downloadGroups) else { return }
        try? data.write(to: groupsURL)
    }

    private func loadGroups() {
        guard let data = try? Data(contentsOf: groupsURL),
              let groups = try? JSONDecoder().decode([DownloadGroup].self, from: data) else { return }
        downloadGroups = groups.compactMap { group in
            let present = group.trackHashes.filter { downloadedHashes.contains($0) }
            guard !present.isEmpty else { return nil }
            return DownloadGroup(id: group.id, kind: group.kind, name: group.name, image: group.image, trackHashes: present)
        }
    }
}

final class DownloadProgressReporter: @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let estimatedTotalBytes: Int64
    private var lastReported: Double = -1
    private let step = 0.02

    init(estimatedTotalBytes: Int64 = 0, onProgress: @escaping (Double) -> Void) {
        self.estimatedTotalBytes = estimatedTotalBytes
        self.onProgress = onProgress
    }

    func report(written: Int64, expected: Int64) {
        let p: Double
        if expected > 0 {
            p = min(max(Double(written) / Double(expected), 0), 1)
        } else if estimatedTotalBytes > 0 {
            p = min(Double(written) / Double(estimatedTotalBytes), 0.99)
        } else {
            return
        }
        guard p - lastReported >= step || (p >= 0.99 && lastReported < 0.99) else { return }
        lastReported = p
        onProgress(p)
    }
}
