import Foundation

// Decisions about downloaded groups, kept free of file and network work so they can be unit tested.
enum DownloadBookkeeping {
    typealias Group = DownloadManager.DownloadGroup

    // Tracks to delete when `group` is removed: the ones no remaining group still contains.
    static func tracksToDelete(removing group: Group, remaining: [Group]) -> [String] {
        let kept = Set(remaining.filter { $0.id != group.id }.flatMap(\.trackHashes))
        return group.trackHashes.filter { !kept.contains($0) }
    }

    // An album's tracks share one image, so its thumbnails stay while any downloaded track still uses it.
    static func isImageInUse(_ image: String, by tracks: [Track]) -> Bool {
        tracks.contains { $0.image == image }
    }

    static func ordered(_ tracks: [Track], in group: Group) -> [Track] {
        let members = Set(group.trackHashes)
        let items = tracks.filter { members.contains($0.trackhash) }
        switch group.kind {
        case .album:
            return items.sorted {
                let d0 = $0.disc ?? 1, d1 = $1.disc ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.trackno ?? 0) < ($1.trackno ?? 0)
            }
        case .folder, .playlist, .mix, .artist:
            var order: [String: Int] = [:]
            for (i, hash) in group.trackHashes.enumerated() where order[hash] == nil { order[hash] = i }
            return items.sorted { (order[$0.trackhash] ?? 0) < (order[$1.trackhash] ?? 0) }
        }
    }

    // On launch, keep each group's tracks that are downloaded or still waiting to download,
    // and drop groups left with neither.
    static func restoredGroups(_ groups: [Group], downloaded: Set<String>, pending: Set<String>) -> [Group] {
        groups.compactMap { group in
            let present = group.trackHashes.filter { downloaded.contains($0) || pending.contains($0) }
            guard !present.isEmpty else { return nil }
            var restored = group
            restored.trackHashes = present
            return restored
        }
    }

    // Unfinished downloads to resume on launch: original order, no duplicates, nothing already downloaded.
    static func resumable(_ pending: [Track], downloaded: Set<String>) -> [Track] {
        var seen = Set<String>()
        return pending.filter { !downloaded.contains($0.trackhash) && seen.insert($0.trackhash).inserted }
    }

    // Offline images to delete with an artist download, minus the ones remaining downloads still show.
    static func imagesToRemove(_ urls: [URL], keeping kept: Set<URL>) -> [URL] {
        urls.filter { !kept.contains($0) }
    }
}
