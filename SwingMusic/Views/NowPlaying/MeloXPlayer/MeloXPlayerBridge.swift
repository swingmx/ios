import Combine
import SwiftUI
import LNPopupUI
import Observation

struct PlaybackBeatTimeline: Equatable {
    func vignettePulse(at time: TimeInterval) -> Double { 0 }
}

extension PlayerStore {
    private var p: AudioPlayer { AudioPlayer.shared }

    var duration: TimeInterval { p.total }
    var isLoading: Bool { false }
    var volume: Double { Double(p.volume) }
    func setVolume(_ value: Double) { p.volume = Float(value) }
    func togglePlayback() { p.toggle() }
    func next() async { p.next() }
    func previous() async { p.prev() }

    var isShuffled: Bool { shuffleOn }
    func toggleShuffle() { p.toggleShuffle() }
    var repeatMode: RepeatMode {
        switch loopMode {
        case .off: .off
        case .all: .all
        case .one: .one
        }
    }
    func cycleRepeatMode() { p.cycleLoop() }

    var queueModeBadgeSystemImage: String? {
        if shuffleOn { return "shuffle" }
        if loopMode != .off { return repeatMode.systemImage }
        return nil
    }

    var queue: [Song] { queueTracks }
    var currentIndex: Int { queueIndex }
    var unplayedQueueIndices: [Int] {
        guard queueIndex + 1 < queueTracks.count else { return [] }
        return Array((queueIndex + 1) ..< queueTracks.count)
    }

    func playFromQueue(at index: Int) async { p.jump(to: index) }

    func moveUpcomingQueueItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = p.index + 1
        guard base < p.queue.count else { return }
        var upcoming = Array(p.queue[base...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        p.queue.replaceSubrange(base..., with: upcoming)
    }

    func addToPlaybackQueue(_ song: Song) {
        p.queue.append(song)
    }

    var isAutoplayEnabled: Bool { autoplayOn }
    func toggleAutoplay() { p.autoplay.toggle() }
    var isAutoMixEnabled: Bool { autoMixOn }
    func toggleAutoMix() {
        p.crossfadeDuration = p.crossfadeDuration > 0 ? 0 : 6
    }
    var isAutoMixTransitioning: Bool { false }
    var autoMixTransitionProgress: Double? { nil }
    var autoMixIncomingSongName: String? { nil }
    var isHeartModeActive: Bool { false }
    func disableHeartMode() {}
    var isListenTogetherSessionActive: Bool { false }
    var availablePlaybackQualities: [MusicQuality] { [] }
    var effectivePlaybackQuality: MusicQuality? { nil }
    func reloadCurrentSongForQualityChange() async {}
    var currentBeatTimeline: PlaybackBeatTimeline? { nil }
    func analyzeCurrentSongBeats() async {}
    func clearCurrentSongBeatAnalysis() {}
}

extension AppSettings {
    var lyricsStyle: LyricsStyle { .appleMusic }
    var playerBackgroundStyle: PlayerBackgroundStyle { .flowingLight }
    var playerScreenAwakeMode: PlayerScreenAwakeMode { .lyrics }
    var playerVolumeControlMode: PlayerVolumeControlMode { .independent }
    var shrinksPausedArtwork: Bool { true }
    var appleMusicLyricsInterfaceAutoHideDelay: Double { 5.0 }
    var beatNetDebugEnabled: Bool { false }
    var playerBackgroundBeatEffectsEnabled: Bool { false }
    var playerBackgroundMotionIntensity: Double { 1.0 }
    var playerBackgroundSaturation: Double { 0.82 }
    var playerBackgroundBlur: Double { 90 }
    var rememberNowPlayingPage: Bool { false }
    var rememberedNowPlayingPage: String {
        get { NowPlayingPage.artwork.rawValue }
        set {}
    }
    var quality: MusicQuality {
        get { MusicQuality.allCases.first! }
        set {}
    }
}

@MainActor
@Observable
final class LyricsStore {
    static let shared = LyricsStore()

    var lyrics: [MXLyricLine] = []
    var errorMessage: String?

    func update(from parsed: ParsedLyrics?) {
        lyrics = parsed?.meloXLines ?? []
        errorMessage = nil
    }
}

struct ArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 0
    var isPopupTransitionTarget: Bool = false

    var body: some View {
        Group {
            if let url {
                Img(urls: [url], radius: 0)
                    .popupTransitionTargetIf(isPopupTransitionTarget)
            } else {
                Color.white.opacity(0.08)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    @ViewBuilder
    func popupTransitionTargetIf(_ isTarget: Bool) -> some View {
        if isTarget { popupTransitionTarget() } else { self }
    }
}

extension Track {
    var artworkURL: URL? {
        API.shared.img(image, size: "medium") ?? API.shared.img(image)
    }

    var largeArtworkURL: URL? {
        API.shared.img(image, size: "original") ?? artworkURL
    }
}

struct HeartModeNowPlayingBadge: View { var body: some View { EmptyView() } }
struct ListenTogetherNowPlayingBadge: View { var body: some View { EmptyView() } }
struct FloatingLyricsButton: View { var body: some View { EmptyView() } }

extension View {
    func keepsScreenAwake(_ isEnabled: Bool) -> some View {
        onChange(of: isEnabled, initial: true) { _, enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
