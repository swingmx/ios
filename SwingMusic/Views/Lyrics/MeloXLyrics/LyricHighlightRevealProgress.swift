import Foundation

enum LyricHighlightRevealProgress {
    static func progress(
        playbackTime: TimeInterval,
        timing: LyricTimingTextAttribute,
        detectionMode: LyricsLongSyllableDetectionMode,
        durationThreshold: TimeInterval
    ) -> Double {
        let duration = timing.endTime - timing.startTime
        let rawProgress = playedProgress(
            playbackTime: playbackTime,
            timing: timing,
            duration: duration
        )
        let regularProgress = smootherStep(rawProgress)
        guard duration > Metrics.attackDuration + Metrics.releaseDuration else {
            return regularProgress
        }

        guard LyricLongToneEmphasis.isLongTone(
            timing: timing,
            detectionMode: detectionMode,
            durationThreshold: durationThreshold
        ) else {
            return regularProgress
        }

        let elapsed = max(playbackTime - timing.startTime, 0)
        let attackProgress = smootherStep(
            elapsed / Metrics.attackDuration
        )
        let releaseStartTime = timing.endTime - Metrics.releaseDuration
        let releaseProgress = smootherStep(
            (playbackTime - releaseStartTime) / Metrics.releaseDuration
        )
        return unitProgress(
            Metrics.attackContribution * attackProgress
                + Metrics.continuousContribution * rawProgress
                + Metrics.releaseContribution * releaseProgress
        )
    }

    private static func playedProgress(
        playbackTime: TimeInterval,
        timing: LyricTimingTextAttribute,
        duration: TimeInterval
    ) -> Double {
        guard playbackTime >= timing.startTime else { return 0 }
        guard playbackTime < timing.endTime else { return 1 }
        guard duration > 0 else { return 1 }
        return unitProgress(
            (playbackTime - timing.startTime) / duration
        )
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

private extension LyricHighlightRevealProgress {
    enum Metrics {
        static let attackDuration: TimeInterval = 0.3
        static let releaseDuration: TimeInterval = 0.16
        static let attackContribution = 0.82
        static let continuousContribution = 0.08
        static let releaseContribution = 0.1
    }
}
