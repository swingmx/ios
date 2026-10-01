import CoreGraphics
import Foundation

enum AMLLWordEmphasis {
    struct UnitBezier {
        private let cx, bx, ax: Double
        private let cy, by, ay: Double

        init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            cx = 3 * x1
            bx = 3 * (x2 - x1) - cx
            ax = 1 - cx - bx
            cy = 3 * y1
            by = 3 * (y2 - y1) - cy
            ay = 1 - cy - by
        }

        private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        private func sampleDerivativeX(_ t: Double) -> Double {
            (3 * ax * t + 2 * bx) * t + cx
        }

        func callAsFunction(_ x: Double) -> Double {
            let x = min(max(x, 0), 1)
            var t = x
            for _ in 0..<8 {
                let error = sampleX(t) - x
                if abs(error) < 1e-6 { return sampleY(t) }
                let derivative = sampleDerivativeX(t)
                if abs(derivative) < 1e-6 { break }
                t -= error / derivative
            }
            var low = 0.0, high = 1.0
            t = x
            for _ in 0..<20 {
                let value = sampleX(t)
                if abs(value - x) < 1e-6 { break }
                if value > x { high = t } else { low = t }
                t = (low + high) / 2
            }
            return sampleY(t)
        }
    }

    private static let bezIn = UnitBezier(0.2, 0.4, 0.58, 1.0)
    private static let bezOut = UnitBezier(0.3, 0.0, 0.58, 1.0)
    private static let easingMid = 0.5

    static func empEasing(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x < easingMid {
            return bezIn(x / easingMid)
        }
        return 1 - bezOut((x - easingMid) / (1 - easingMid))
    }

    static func shouldEmphasize(
        duration: TimeInterval,
        characterCount: Int,
        isCJK: Bool
    ) -> Bool {
        guard duration >= 1 else { return false }
        if isCJK { return true }
        return characterCount > 1 && characterCount <= 7
    }

    struct Amounts: Equatable {
        let amount: Double
        let blur: Double
        let animationDuration: TimeInterval
    }

    static func amounts(
        duration: TimeInterval,
        isLastWordOfLine: Bool
    ) -> Amounts {
        var du = max(1, duration)

        var amount = du / 2
        amount = amount > 1 ? amount.squareRoot() : amount * amount * amount
        var blur = du / 3
        blur = blur > 1 ? blur.squareRoot() : blur * blur * blur

        amount *= 0.6
        blur *= 0.5

        if isLastWordOfLine {
            amount *= 1.6
            blur *= 1.5
            du *= 1.2
        }

        return Amounts(
            amount: min(1.2, amount),
            blur: min(0.8, blur),
            animationDuration: du
        )
    }

    struct GlyphState: Equatable {
        let scale: Double
        let offsetXEm: Double
        let offsetYEm: Double
        let glowAlpha: Double
        let glowRadiusEm: Double
        let floatEm: Double

        static let neutral = GlyphState(
            scale: 1, offsetXEm: 0, offsetYEm: 0,
            glowAlpha: 0, glowRadiusEm: 0, floatEm: 0
        )
    }

    static func glyphState(
        playbackTime: TimeInterval,
        wordStartTime: TimeInterval,
        index: Int,
        count: Int,
        amounts: Amounts
    ) -> GlyphState {
        let count = max(count, 1)
        let index = min(max(index, 0), count - 1)
        let du = amounts.animationDuration

        let characterDelay = du / 2.5 / Double(count) * Double(index)
        let start = wordStartTime + characterDelay

        let progress = (playbackTime - start) / du
        let eased = empEasing(progress)

        let scale = 1 + eased * 0.1 * amounts.amount
        let offsetX = -eased * 0.03 * amounts.amount
            * (Double(count) / 2 - Double(index))
        let offsetY = -eased * 0.025 * amounts.amount

        let floatProgress = (playbackTime - (start - 0.4)) / (du * 1.4)
        let floatEm: Double
        if floatProgress <= 0 {
            floatEm = 0
        } else if floatProgress >= 1 {
            floatEm = 0
        } else {
            floatEm = -sin(floatProgress * .pi) * 0.05
        }

        return GlyphState(
            scale: scale,
            offsetXEm: offsetX,
            offsetYEm: offsetY,
            glowAlpha: eased * amounts.blur,
            glowRadiusEm: min(0.3, amounts.blur * 0.3),
            floatEm: floatEm
        )
    }

    static func baseFloatEm(
        playbackTime: TimeInterval,
        wordStartTime: TimeInterval,
        wordEndTime: TimeInterval,
        isBackgroundLine: Bool = false
    ) -> Double {
        let up = isBackgroundLine ? 0.1 : 0.05
        let duration = max(1, wordEndTime - wordStartTime)
        let progress = (playbackTime - wordStartTime) / duration
        if progress <= 0 { return 0 }
        if progress >= 1 { return -up }
        return -up * easeOut(min(max(progress, 0), 1))
    }

    private static let easeOutCurve = UnitBezier(0, 0, 0.58, 1)
    private static func easeOut(_ x: Double) -> Double { easeOutCurve(x) }
}
