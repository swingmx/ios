import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class ActivityManager {
    static let shared = ActivityManager()
    private var activity: Activity<MusicAttributes>?
    private let appGroup = "group.swingmusic"
    private let widgetKind = "SwingMusicNowPlaying"
    private var lastPersisted: MusicAttributes.ContentState?
    private var lastProgressAt = Date.distantPast
    private init() {}

    func start(track: Track, accentHex: String) async {
        let state = MusicAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            album: track.album,
            playing: true,
            progress: 0,
            duration: Double(track.duration),
            imageData: activity?.content.state.imageData,
            accentHex: accentHex
        )

        persistWidget(state, forceReload: true)
    }

    func updateState(playing: Bool, progress: Double, duration: Double? = nil) async {
        if let a = activity {
            var s = a.content.state
            s.playing = playing
            s.progress = progress
            if let duration { s.duration = duration }
            await a.update(ActivityContent(state: s, staleDate: nil))
            persistWidget(s, forceReload: false)
            return
        }

        var fallback = lastPersisted ?? currentWidgetState()
        fallback.playing = playing
        fallback.progress = progress
        if let duration { fallback.duration = duration }
        persistWidget(fallback, forceReload: false)
    }

    func updateImage(_ data: Data) async {
        let compressed: Data? = {
            guard let img = UIImage(data: data) else { return nil }
            let thumb = img.preparingThumbnail(of: CGSize(width: 80, height: 80)) ?? img
            return thumb.jpegData(compressionQuality: 0.5)
        }()
        let imageData = compressed ?? data

        if let a = activity {
            var s = a.content.state
            s.imageData = imageData
            await a.update(ActivityContent(state: s, staleDate: nil))
            persistWidget(s, forceReload: true)
            addToHistory(s)
            return
        }

        var fallback = currentWidgetState()
        fallback.imageData = imageData
        persistWidget(fallback, forceReload: true)
        addToHistory(fallback)
    }

    func updateAccent(_ color: Color) async {
        let hex = colorHex(color)

        if let a = activity {
            var s = a.content.state
            s.accentHex = hex
            await a.update(ActivityContent(state: s, staleDate: nil))
            persistWidget(s, forceReload: true)
            return
        }

        var fallback = currentWidgetState()
        fallback.accentHex = hex
        persistWidget(fallback, forceReload: true)
    }

    func updateTrack(_ track: Track, accentHex: String) async {
        guard let a = activity else {
            await start(track: track, accentHex: accentHex)
            return
        }

        let s = MusicAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            album: track.album,
            playing: true,
            progress: 0,
            duration: Double(track.duration),
            imageData: a.content.state.imageData,
            accentHex: accentHex
        )
        await a.update(ActivityContent(state: s, staleDate: nil))
        persistWidget(s, forceReload: true)
    }

    func end() async {
        if let a = activity {
            var s = a.content.state
            s.playing = false
            persistWidget(s, forceReload: true)
            await a.end(ActivityContent(state: s, staleDate: nil), dismissalPolicy: .immediate)
        } else {
            clearWidgetState()
        }
        activity = nil
    }

    private func persistWidget(_ state: MusicAttributes.ContentState, forceReload: Bool) {
        PerformanceTracer.shared.measure(.widgetWrite) {
            persistWidgetTraced(state, forceReload: forceReload)
        }
    }

    private func persistWidgetTraced(_ state: MusicAttributes.ContentState, forceReload: Bool) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }

        let previous = lastPersisted
        // The widget draws progress from w.progressAt itself, so progress is only written when it jumps.
        let now = Date()
        let expected = previous.map { $0.playing ? $0.progress + now.timeIntervalSince(lastProgressAt) : $0.progress }
        let moved = expected.map { abs($0 - state.progress) > 2 } ?? true
        var routine = state
        routine.progress = previous?.progress ?? state.progress
        guard forceReload || moved || routine != previous else { return }

        if previous?.title != state.title { d.set(state.title, forKey: "w.title") }
        if previous?.artist != state.artist { d.set(state.artist, forKey: "w.artist") }
        if previous?.album != state.album { d.set(state.album, forKey: "w.album") }
        if previous?.playing != state.playing { d.set(state.playing, forKey: "w.playing") }
        var saved = state
        if moved || previous?.playing != state.playing {
            d.set(state.progress, forKey: "w.progress")
            d.set(now.timeIntervalSince1970, forKey: "w.progressAt")
            lastProgressAt = now
        } else if let previous {
            saved.progress = previous.progress
        }
        if previous?.duration != state.duration { d.set(state.duration, forKey: "w.duration") }
        if previous?.imageData != state.imageData { d.set(state.imageData, forKey: "w.image") }
        if previous?.accentHex != state.accentHex { d.set(state.accentHex, forKey: "w.accent") }
        lastPersisted = saved
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private func currentWidgetState() -> MusicAttributes.ContentState {
        let d = UserDefaults(suiteName: appGroup)
        return MusicAttributes.ContentState(
            title: d?.string(forKey: "w.title") ?? "Not Playing",
            artist: d?.string(forKey: "w.artist") ?? "-",
            album: d?.string(forKey: "w.album") ?? "",
            playing: d?.bool(forKey: "w.playing") ?? false,
            progress: d?.double(forKey: "w.progress") ?? 0,
            duration: d?.double(forKey: "w.duration") ?? 0,
            imageData: d?.data(forKey: "w.image"),
            accentHex: d?.string(forKey: "w.accent") ?? "#FF375F"
        )
    }

    private func clearWidgetState() {
        let state = MusicAttributes.ContentState(
            title: "Not Playing",
            artist: "-",
            album: "",
            playing: false,
            progress: 0,
            duration: 0,
            imageData: nil,
            accentHex: "#FF375F"
        )
        persistWidget(state, forceReload: true)
    }

    private func addToHistory(_ state: MusicAttributes.ContentState) {
        guard let d = UserDefaults(suiteName: appGroup), let img = state.imageData else { return }

        let newRecent = RecentTrack(
            title: state.title,
            artist: state.artist,
            imageData: img,
            accentHex: state.accentHex
        )

        var history: [RecentTrack] = []
        if let data = d.data(forKey: "w.history"),
           let cached = try? JSONDecoder().decode([RecentTrack].self, from: data) {
            history = cached
        }

        history.removeAll(where: { $0.title == newRecent.title })
        history.insert(newRecent, at: 0)
        if history.count > 4 { history = Array(history.prefix(4)) }

        if let encoded = try? JSONEncoder().encode(history) {
            d.set(encoded, forKey: "w.history")
        }
    }

    private func colorHex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
