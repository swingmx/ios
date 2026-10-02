import Foundation
import Combine

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [String: DownloadState] = [:]
    @Published var downloadedTracks: [Track] = []
    @Published var downloadedHashes: Set<String> = []
    @Published var downloadGroups: [DownloadGroup] = []
    // Downloaded mixes by mix id, for showing and opening them from Downloads.
    @Published private(set) var savedMixes: [String: Mix] = [:]

    struct DownloadGroup: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case album, playlist, folder, mix, artist }
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

    private var pendingURL: URL {
        downloadsDir.appendingPathComponent("pending.json")
    }

    private init() {
        loadMetadata()
        loadPending()
        loadGroups()
        savedMixes = Dictionary(MixOfflineStore.shared.all().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        resumePending()
        Task(priority: .utility) { await backfillOfflineImages() }
    }

    nonisolated static func artistGroupID(_ artisthash: String) -> String { "artist:\(artisthash)" }
    nonisolated static func mixGroupID(_ mixID: String) -> String { "mix:\(mixID)" }

    // The album hash, artist hash, mix id, etc. a group was created for: its id after the "kind:" prefix.
    nonisolated static func itemID(of group: DownloadGroup) -> String {
        guard let colon = group.id.firstIndex(of: ":") else { return group.id }
        return String(group.id[group.id.index(after: colon)...])
    }

    var ungroupedTracks: [Track] {
        let grouped = Set(downloadGroups.flatMap { $0.trackHashes })
        return downloadedTracks.filter { !grouped.contains($0.trackhash) }
    }

    func tracks(in group: DownloadGroup) -> [Track] {
        DownloadBookkeeping.ordered(downloadedTracks, in: group)
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
        rememberUnfinished(track)
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

    // Tracks that another downloaded group also contains are kept.
    func removeGroup(_ group: DownloadGroup) {
        let group = downloadGroups.first { $0.id == group.id } ?? group
        downloadGroups.removeAll { $0.id == group.id }
        let byHash = Dictionary(downloadedTracks.map { ($0.trackhash, $0) }, uniquingKeysWith: { a, _ in a })
        for hash in DownloadBookkeeping.tracksToDelete(removing: group, remaining: downloadGroups) {
            if let track = byHash[hash] {
                removeDownload(track)
            } else {
                cancelPending(hash)
            }
        }
        switch group.kind {
        case .artist: removeArtistSnapshot(Self.itemID(of: group))
        case .mix: removeMixSnapshot(Self.itemID(of: group))
        case .album, .playlist, .folder: break
        }
        saveGroups()
    }

    func removeDownload(_ track: Track) {
        pendingQueue.removeAll { $0.trackhash == track.trackhash }
        forgetUnfinished(track.trackhash)
        let file = localURL(for: track)
        try? fileManager.removeItem(at: file)
        downloads.removeValue(forKey: track.trackhash)
        downloadedTracks.removeAll { $0.trackhash == track.trackhash }
        downloadedHashes.remove(track.trackhash)
        if !DownloadBookkeeping.isImageInUse(track.image, by: downloadedTracks) {
            removeThumbnails(for: track)
        }
        saveMetadata()
    }

    // Stops a track that has not finished downloading. One already transferring is discarded when it completes.
    private func markFailed(_ track: Track) {
        if cancelled.remove(track.trackhash) != nil {
            downloads.removeValue(forKey: track.trackhash)
        } else {
            downloads[track.trackhash] = .failed
        }
    }

    private func cancelPending(_ hash: String) {
        pendingQueue.removeAll { $0.trackhash == hash }
        forgetUnfinished(hash)
        if case .downloading = downloads[hash] {
            cancelled.insert(hash)
        }
        downloads.removeValue(forKey: hash)
    }

    func removeAll() {
        pendingQueue.removeAll()
        for track in downloadedTracks {
            let file = localURL(for: track)
            try? fileManager.removeItem(at: file)
        }
        for group in downloadGroups {
            switch group.kind {
            case .artist: ArtistOfflineStore.shared.remove(Self.itemID(of: group))
            case .mix: MixOfflineStore.shared.remove(Self.itemID(of: group))
            case .album, .playlist, .folder: break
            }
        }
        savedMixes.removeAll()
        cancelled.formUnion(downloads.compactMap { hash, state in
            if case .downloading = state { return hash }
            return nil
        })
        downloads.removeAll()
        downloadedTracks.removeAll()
        downloadedHashes.removeAll()
        downloadGroups.removeAll()
        unfinished.removeAll()
        saveMetadata()
        saveGroups()
        savePending()
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
            markFailed(track)
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
                markFailed(track)
                return
            }

            let destinationURL = localURL(for: track)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: localURLTemp, to: destinationURL)

            if cancelled.remove(track.trackhash) != nil {
                try? fileManager.removeItem(at: destinationURL)
                return
            }

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
            forgetUnfinished(track.trackhash)
            Log.info("download", "Completed \(track.title)")

            if !downloadedTracks.contains(where: { $0.trackhash == track.trackhash }) {
                downloadedTracks.append(track)
                downloadedHashes.insert(track.trackhash)
            }
            saveMetadata()
        } catch {
            Log.error("download", "Failed \(track.title): \(error.localizedDescription)")
            markFailed(track)
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

    // Track artwork sizes kept offline: original for the album header and Now Playing, large ("") for
    // album cards, medium and small for lists.
    nonisolated static let trackImageSizes = ["original", "", "medium", "small"]

    nonisolated static func thumbnailURLs(for track: Track) -> [URL] {
        trackImageSizes.compactMap { API.shared.img(track.image, size: $0) }
    }

    // An album's tracks share one image, so images already saved are skipped rather than fetched per track.
    private func cacheThumbnails(for track: Track) async {
        await cacheOfflineImages(Self.thumbnailURLs(for: track))
    }

    private func removeThumbnails(for track: Track) {
        for url in Self.thumbnailURLs(for: track) { ImageDiskCache.removeOffline(for: url) }
    }

    // Downloads saved before the sharper sizes were kept get them the next time the app can reach the server.
    private func backfillOfflineImages() async {
        var seen = Set<String>()
        let urls = downloadedTracks.filter { seen.insert($0.image).inserted }.flatMap(Self.thumbnailURLs(for:))
            + savedMixes.values.flatMap(\.offlineImageURLs)
        await cacheOfflineImages(urls)
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
        downloadGroups = DownloadBookkeeping.restoredGroups(
            groups, downloaded: downloadedHashes, pending: Set(unfinished.map(\.trackhash)))
    }

    // MARK: Unfinished downloads
    // The download queue lives in memory, so unfinished tracks are saved and resumed on the next launch.

    private var unfinished: [Track] = []
    private var cancelled: Set<String> = []
    private var pendingSaveScheduled = false

    private func rememberUnfinished(_ track: Track) {
        guard !unfinished.contains(where: { $0.trackhash == track.trackhash }) else { return }
        unfinished.append(track)
        savePending()
    }

    private func forgetUnfinished(_ hash: String) {
        guard let i = unfinished.firstIndex(where: { $0.trackhash == hash }) else { return }
        unfinished.remove(at: i)
        savePending()
    }

    private func savePending() {
        guard !pendingSaveScheduled else { return }
        pendingSaveScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            pendingSaveScheduled = false
            guard let data = try? JSONEncoder().encode(unfinished) else { return }
            let url = pendingURL
            Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func loadPending() {
        guard let data = try? Data(contentsOf: pendingURL),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return }
        unfinished = DownloadBookkeeping.resumable(tracks, downloaded: downloadedHashes)
    }

    private func resumePending() {
        let tracks = unfinished
        guard !tracks.isEmpty else { return }
        Log.info("download", "Resuming \(tracks.count) unfinished downloads")
        for track in tracks { download(track) }
    }

    // MARK: Artists

    // Saves what the artist screen needs offline, then downloads every track the artist has right now.
    func downloadArtist(_ artisthash: String) async {
        do {
            let snapshot = try await API.shared.artistSnapshot(artisthash)
            let detail = try JSONDecoder().decode(ArtistDetail.self, from: snapshot.detail)
            let tracks = try JSONDecoder().decode([Track].self, from: snapshot.tracks)
            try ArtistOfflineStore.shared.save(artistHash: artisthash, detail: snapshot.detail, tracks: snapshot.tracks)
            downloadAll(tracks, group: DownloadGroup(
                id: Self.artistGroupID(artisthash), kind: .artist, name: detail.artist.name,
                image: detail.artist.image, trackHashes: tracks.map(\.trackhash)))
            await cacheOfflineImages(ArtistOfflineStore.imageURLs(for: detail))
        } catch {
            Log.error("download", "Artist \(artisthash) download failed: \(error.localizedDescription)")
        }
    }

    // MARK: Mixes

    // Saves the mix as shown (title, description, artwork), then downloads its tracks.
    func downloadMix(_ mix: Mix, tracks: [Track]) async {
        do {
            try MixOfflineStore.shared.save(mix)
            savedMixes[mix.id] = mix
        } catch {
            Log.error("download", "Saving mix \(mix.id) failed: \(error.localizedDescription)")
        }
        downloadAll(tracks, group: DownloadGroup(
            id: Self.mixGroupID(mix.id), kind: .mix, name: mix.title,
            image: mix.imageFile ?? "", trackHashes: tracks.map(\.trackhash)))
        await cacheOfflineImages(mix.offlineImageURLs)
    }

    private func removeMixSnapshot(_ mixID: String) {
        if let mix = savedMixes[mixID] ?? MixOfflineStore.shared.mix(for: mixID) {
            for url in DownloadBookkeeping.imagesToRemove(mix.offlineImageURLs, keeping: thumbnailsInUse()) {
                ImageDiskCache.removeOffline(for: url)
            }
        }
        MixOfflineStore.shared.remove(mixID)
        savedMixes.removeValue(forKey: mixID)
    }

    // Track thumbnails remaining downloads still show, which removed groups must leave in place.
    private func thumbnailsInUse() -> Set<URL> {
        Set(downloadedTracks.flatMap(Self.thumbnailURLs(for:)))
    }

    private func cacheOfflineImages(_ urls: [URL]) async {
        for url in urls where !ImageDiskCache.hasOffline(for: url) {
            var req = URLRequest(url: url)
            if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
            guard let (data, resp) = try? await Net.session.data(for: req),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
            ImageDiskCache.storeOffline(data, for: url)
        }
    }

    private func removeArtistSnapshot(_ artisthash: String) {
        let store = ArtistOfflineStore.shared
        if let detail = store.detail(for: artisthash) {
            for url in DownloadBookkeeping.imagesToRemove(ArtistOfflineStore.imageURLs(for: detail), keeping: thumbnailsInUse()) {
                ImageDiskCache.removeOffline(for: url)
            }
        }
        store.remove(artisthash)
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
