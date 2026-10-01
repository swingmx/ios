import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let lyricsFocusPositionRange = 0.05 ... 0.8
    static let lyricsCurrentLineScaleRange = 1.0 ... 1.5
    static let lyricsFocusCascadeChaseSpeedGradientRange = 0.0 ... 1.0
    static let lyricsFocusCascadeBounceRange = 0.0 ... 0.8
    static let lyricsFocusCascadeBounceGradientRange = 0.0 ... 1.0
    static let lyricsFocusScaleBounceRange = 0.0 ... 0.5
    static let lyricsFocusScaleBounceDurationRange = 0.15 ... 0.8
    static let lyricsFocusColorLeadTimeRange = -0.3 ... 0.3

    var lyricsFontSize: Double = 32.0
    var lyricsFontWeight: LyricsFontWeight = .heavy
    var lyricsCurrentLineScale: Double = 1.02
    var lyricsLineSpacing: Double = 28.0
    var lyricsBlurIntensity: Double = 0.8
    var lyricsUsesUniformDimmingWhileBrowsing: Bool = true
    var lyricsDistanceBlurScale: Double = 1.05
    var lyricsHiddenInterfaceBlurScale: Double = 0.85
    var lyricsDimAmount: Double = 1.0

    var lyricsTapToSeek: Bool = true
    var lyricsLongPressToShare: Bool = true
    var lyricsAutoFollow: Bool = true
    var lyricsFollowDelay: Double = 3
    var appleMusicLyricsScrollHideThreshold: Double = 200.0

    var lyricsWordByWord: Bool = true
    var lyricsPseudoWordByWord: Bool = false
    var lyricsLiftMode: LyricsLiftMode = .character
    var lyricsHighlightGradientWidth: Double = 0.7
    var lyricsHighlightGradientReduction: Double = 0.65
    var lyricsEmphasisStyle: LyricsEmphasisStyle = .amll

    var lyricsGlowEnabled: Bool = true
    var lyricsGlowIntensity: Double = 1
    var lyricsGlowLongSyllablesOnly: Bool = true
    var lyricsLongSyllableDetectionMode: LyricsLongSyllableDetectionMode = .character
    var lyricsLongSyllableDurationThreshold: Double = 0.95
    var lyricsLongToneExpansionAmount: Double = 0.05

    var lyricsFocusPosition: Double = 0.25
    var lyricsFocusCascadeDelay: Double = 0.021
    var lyricsFocusCascadeDelayIncrease: Double = 0.005
    var lyricsFocusCascadeFollowingDelay: Double = 0.048
    var lyricsFocusCascadeCatchUpRatio: Double = 0.97
    var lyricsFocusCascadeChaseSpeedGradient: Double = 0.70
    var lyricsFocusCascadeDuration: Double = 0.74
    var lyricsFocusSnapThreshold: Double = 0.26
    var lyricsFocusCascadeBounceEnabled: Bool = true
    var lyricsFocusCascadeBounce: Double = 0.26
    var lyricsFocusCascadeBounceGradient: Double = 0.85
    var lyricsFocusScaleBounceEnabled: Bool = true
    var lyricsFocusScaleBounce: Double = 0.32
    var lyricsFocusScaleBounceDuration: Double = 0.58
    var lyricsFocusColorLeadTime: Double = 0.0

    var lyricsInterludeCountdownEnabled: Bool = true

    var lyricsTranslationEnabled: Bool = true
    var lyricsTranslationDisplayMode: LyricsTranslationDisplayMode = .focusedLine
    var lyricsTranslationFontScale: Double = 0.65
    var lyricsTranslationOpacity: Double = 0.9
    var lyricsRomanizationEnabled: Bool = true
    var lyricsRomanizationDisplayMode: LyricsTranslationDisplayMode = .focusedLine
    var lyricsRomanizationFontScale: Double = 0.65
    var lyricsRomanizationOpacity: Double = 0.9

    var lyricsAdvanceTime: Double = 0.15
    var lyricsAdvanceTimeAppliesToWordByWord: Bool = true

    var wordByWordLyricsAdvanceTime: TimeInterval {
        lyricsAdvanceTimeAppliesToWordByWord ? lyricsAdvanceTime : 0
    }

    func effectiveLyricsAdvanceTime(hasSyllableSyncedLyrics: Bool) -> TimeInterval {
        hasSyllableSyncedLyrics ? wordByWordLyricsAdvanceTime : lyricsAdvanceTime
    }

    func effectiveLyricsAdvanceTime(for lyrics: [MXLyricLine]) -> TimeInterval {
        effectiveLyricsAdvanceTime(
            hasSyllableSyncedLyrics: lyrics.contains(where: \.isSyllableSynced)
        )
    }
}
