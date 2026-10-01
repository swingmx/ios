import CoreGraphics
import Foundation
import SwiftUI

enum LyricLongToneEmphasis {
    struct State {
        let isLongTone: Bool
        let envelope: Double
        let expansionAmount: Double
        let glowAmount: Double
        private let characterIndex: Int
        private let characterCount: Int

        init(
            isLongTone: Bool,
            envelope: Double,
            expansionAmount: Double,
            glowAmount: Double,
            characterIndex: Int,
            characterCount: Int
        ) {
            self.isLongTone = isLongTone
            self.envelope = envelope
            self.expansionAmount = expansionAmount
            self.glowAmount = glowAmount
            self.characterIndex = characterIndex
            self.characterCount = characterCount
        }

        static let inactive = State(
            isLongTone: false,
            envelope: 0,
            expansionAmount: 0,
            glowAmount: 0,
            characterIndex: 0,
            characterCount: 1
        )

        func expansionOffset(
            layoutDirection: LayoutDirection,
            glyphBounds: CGRect
        ) -> CGSize {
            guard envelope > 0, expansionAmount > 0 else {
                return .zero
            }

            let count = max(characterCount, 1)
            var index = min(max(characterIndex, 0), count - 1)
            if layoutDirection == .rightToLeft {
                index = count - index - 1
            }

            let distanceFromCenter = Double(count - 1) * 0.5
                - Double(index)
            let em = max(glyphBounds.height, 1)
            let intensity = CGFloat(envelope * expansionAmount)
            return CGSize(
                width: -intensity
                    * Metrics.horizontalOffsetRatio
                    * em
                    * CGFloat(distanceFromCenter),
                height: -intensity
                    * Metrics.verticalOffsetRatio
                    * em
            )
        }
    }

    static func state(
        playbackTime: TimeInterval,
        timing: LyricTimingTextAttribute,
        detectionMode: LyricsLongSyllableDetectionMode,
        durationThreshold: TimeInterval
    ) -> State {
        let group = timingGroup(
            for: timing,
            detectionMode: detectionMode
        )
        let duration = max(group.endTime - group.startTime, 0)
        guard qualifiesAsLongTone(
            timing: timing,
            duration: duration,
            durationThreshold: durationThreshold
        ) else {
            return .inactive
        }

        let count = max(group.characterCount, 1)
        let index = min(max(group.characterIndex, 0), count - 1)
        let staggerDelay: TimeInterval
        if count > 1 {
            staggerDelay = duration
                * Metrics.staggerSpanRatio
                * Double(index)
                / Double(count - 1)
        } else {
            staggerDelay = 0
        }

        let animationDuration = max(
            duration,
            Metrics.minimumAnimationDuration
        )
        let progress = (
            playbackTime - group.startTime - staggerDelay
        ) / animationDuration

        return State(
            isLongTone: true,
            envelope: emphasisEnvelope(progress),
            expansionAmount: expansionAmount(
                duration: duration,
                threshold: durationThreshold
            ),
            glowAmount: glowAmount(
                duration: duration,
                threshold: durationThreshold
            ),
            characterIndex: index,
            characterCount: count
        )
    }

    static func isLongTone(
        timing: LyricTimingTextAttribute,
        detectionMode: LyricsLongSyllableDetectionMode,
        durationThreshold: TimeInterval
    ) -> Bool {
        let group = timingGroup(
            for: timing,
            detectionMode: detectionMode
        )
        return qualifiesAsLongTone(
            timing: timing,
            duration: max(group.endTime - group.startTime, 0),
            durationThreshold: durationThreshold
        )
    }

    private static func qualifiesAsLongTone(
        timing: LyricTimingTextAttribute,
        duration: TimeInterval,
        durationThreshold: TimeInterval
    ) -> Bool {
        !timing.isWhitespace
            && duration >= max(durationThreshold, 0)
    }

    private static func timingGroup(
        for timing: LyricTimingTextAttribute,
        detectionMode: LyricsLongSyllableDetectionMode
    ) -> TimingGroup {
        if timing.usesWordTimingForLongTone {
            return TimingGroup(
                startTime: timing.wordStartTime,
                endTime: timing.wordEndTime,
                characterIndex: timing.wordCharacterIndex,
                characterCount: timing.wordCharacterCount
            )
        }

        return switch detectionMode {
        case .word:
            TimingGroup(
                startTime: timing.wordStartTime,
                endTime: timing.wordEndTime,
                characterIndex: timing.wordCharacterIndex,
                characterCount: timing.wordCharacterCount
            )
        case .character:
            TimingGroup(
                startTime: timing.syllableStartTime,
                endTime: timing.syllableEndTime,
                characterIndex: timing.characterIndex,
                characterCount: timing.characterCount
            )
        }
    }

    private static func emphasisEnvelope(_ value: Double) -> Double {
        let progress = unitProgress(value)
        if progress <= Metrics.peakProgress {
            return smootherStep(progress / Metrics.peakProgress)
        }
        return 1 - smootherStep(
            (progress - Metrics.peakProgress)
                / (1 - Metrics.peakProgress)
        )
    }

    private static func expansionAmount(
        duration: TimeInterval,
        threshold: TimeInterval
    ) -> Double {
        emphasisAmount(
            duration: duration,
            threshold: threshold,
            fullStrengthDuration: Metrics.fullExpansionDuration,
            minimumAmount: Metrics.minimumExpansionAmount,
            maximumAmount: Metrics.maximumExpansionAmount
        )
    }

    private static func glowAmount(
        duration: TimeInterval,
        threshold: TimeInterval
    ) -> Double {
        emphasisAmount(
            duration: duration,
            threshold: threshold,
            fullStrengthDuration: Metrics.fullGlowDuration,
            minimumAmount: Metrics.minimumGlowAmount,
            maximumAmount: Metrics.maximumGlowAmount
        )
    }

    private static func emphasisAmount(
        duration: TimeInterval,
        threshold: TimeInterval,
        fullStrengthDuration: TimeInterval,
        minimumAmount: Double,
        maximumAmount: Double
    ) -> Double {
        let minimumDuration = max(threshold, 0)
        let fullStrengthDuration = max(
            fullStrengthDuration,
            minimumDuration + 0.001
        )
        let progress = smootherStep(
            (duration - minimumDuration)
                / (fullStrengthDuration - minimumDuration)
        )
        return minimumAmount
            + (maximumAmount - minimumAmount)
                * progress
    }

    private static func smootherStep(_ value: Double) -> Double {
        let progress = unitProgress(value)
        return progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private static func unitProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private extension LyricLongToneEmphasis {
    struct TimingGroup {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let characterIndex: Int
        let characterCount: Int
    }

    enum Metrics {
        static let minimumAnimationDuration: TimeInterval = 1
        static let staggerSpanRatio = 0.55
        static let peakProgress = 0.5
        static let fullExpansionDuration: TimeInterval = 2.8
        static let minimumExpansionAmount = 0.7
        static let maximumExpansionAmount = 1.0
        static let horizontalOffsetRatio: CGFloat = 0.03
        static let verticalOffsetRatio: CGFloat = 0.025
        static let fullGlowDuration: TimeInterval = 2.8
        static let minimumGlowAmount = 0.32
        static let maximumGlowAmount = 0.7
    }
}
