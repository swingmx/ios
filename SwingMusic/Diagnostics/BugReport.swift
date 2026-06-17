import Foundation
import UIKit

enum DeviceInfo {
    static var model: String {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
    static var systemVersion: String { UIDevice.current.systemVersion }
    static var locale: String { Locale.current.identifier }

    static var freeDisk: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let bytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static var memory: String {
        let total = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory)
    }
}

struct BugReport: Identifiable {
    let id: String
    let date: Date

    var note: String

    let appVersion: String
    let device: String
    let systemVersion: String
    let locale: String
    let freeDisk: String
    let memory: String

    let serverURL: String
    let authed: Bool

    let nowPlaying: String
    let queueInfo: String
    let downloadInfo: String

    let logs: String

    static func newID() -> String {
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        func group(_ n: Int) -> String { String((0..<n).compactMap { _ in chars.randomElement() }) }
        return "SM-\(group(4))-\(group(4))"
    }

    @MainActor
    static func generate(note: String = "") -> BugReport {
        let player = AudioPlayer.shared
        let dl = DownloadManager.shared

        let nowPlaying: String
        if let t = player.current {
            let artist = t.artists?.first?.name ?? "Unknown"
            let state = player.playing ? "playing" : "paused"
            let pos = "\(Int(player.time).mmss)/\(Int(player.total).mmss)"
            let quality = "\(t.bitrate.map { "\($0)kbps" } ?? "?") · \(player.audioQuality.rawValue)"
            let offline = dl.isDownloaded(t) ? "offline" : "stream"
            nowPlaying = "\(t.title) — \(artist) [\(state) \(pos), \(quality), \(offline), shuffle \(player.shuffle ? "on" : "off")]"
        } else {
            nowPlaying = "Nothing playing"
        }

        let queueInfo = "\(player.queue.count) tracks, index \(player.index)"
        let downloadInfo = "\(dl.downloadedTracks.count) songs · \(dl.totalSize)"

        return BugReport(
            id: newID(),
            date: Date(),
            note: note,
            appVersion: AppInfo.versionString,
            device: DeviceInfo.model,
            systemVersion: DeviceInfo.systemVersion,
            locale: DeviceInfo.locale,
            freeDisk: DeviceInfo.freeDisk,
            memory: DeviceInfo.memory,
            serverURL: API.shared.base,
            authed: API.shared.authed,
            nowPlaying: nowPlaying,
            queueInfo: queueInfo,
            downloadInfo: downloadInfo,
            logs: Log.shared.text()
        )
    }

    var plainText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return """
        Swing Music — Bug Report
        ========================
        Report ID:   \(id)
        Date:        \(f.string(from: date))

        What happened
        -------------
        \(note.isEmpty ? "(no description provided)" : note)

        App
        ---
        Version:     \(appVersion)
        Server:      \(serverURL)
        Signed in:   \(authed ? "yes" : "no")

        Device
        ------
        Model:       \(device)
        iOS:         \(systemVersion)
        Locale:      \(locale)
        Free space:  \(freeDisk)
        Memory:      \(memory)

        Playback
        --------
        Now playing: \(nowPlaying)
        Queue:       \(queueInfo)
        Downloads:   \(downloadInfo)

        Recent log (\(Log.shared.entries.count) entries)
        ----------
        \(logs)
        """
    }
}
