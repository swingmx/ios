import SwiftUI

struct LyricTimingTextAttribute: TextAttribute, Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let syllableStartTime: TimeInterval
    let syllableEndTime: TimeInterval
    let characterIndex: Int
    let characterCount: Int
    let wordStartTime: TimeInterval
    let wordEndTime: TimeInterval
    let wordCharacterIndex: Int
    let wordCharacterCount: Int
    let usesWordTimingForLongTone: Bool
    let isWhitespace: Bool
    var isLastWordInLine: Bool = false
}

struct LyricGlowTextRenderer: TextRenderer {
    struct Style: Equatable, Sendable {
        let glowRadius: CGFloat
        let glowOpacity: Double
        let glowsLongSyllablesOnly: Bool
        let longSyllableDetectionMode:
            LyricsLongSyllableDetectionMode
        let longSyllableDurationThreshold: TimeInterval
        let unplayedOpacity: Double
        let maximumUnplayedBlurRadius: CGFloat
        let playedRise: CGFloat
        let maximumLongSyllableScale: CGFloat
        let longSyllableExpansionPadding: CGFloat
        let highlightGradientWidth: CGFloat
        let highlightGradientReduction: CGFloat
        let liftMode: LyricsLiftMode
        var emphasisStyle: LyricsEmphasisStyle = .meloX
        var emSize: CGFloat = 0

        fileprivate var drawsGlow: Bool {
            glowRadius > 0 && glowOpacity > 0
        }

        fileprivate var usesAMLLEmphasis: Bool {
            emphasisStyle == .amll && emSize > 0
        }
    }

    struct LayoutConfiguration: Equatable, Sendable {
        let width: CGFloat?
        let centersLines: Bool
        let trailingVisualOverflow: CGFloat

        init(
            width: CGFloat?,
            centersLines: Bool,
            trailingVisualOverflow: CGFloat = 0
        ) {
            self.width = width
            self.centersLines = centersLines
            self.trailingVisualOverflow = trailingVisualOverflow
        }

        fileprivate var constrainedWidth: CGFloat? {
            guard let width, width.isFinite, width > 0 else { return nil }
            return width
        }
    }

    static let glowTailDuration: TimeInterval = 0.55

    var playbackTime: TimeInterval
    let style: Style
    let layoutConfiguration: LayoutConfiguration
    let appliesTimingEffects: Bool
    var timingEffectsStrength: Double

    var animatableData: Double {
        get { timingEffectsStrength }
        set { timingEffectsStrength = newValue }
    }

    var displayPadding: EdgeInsets {
        let padding = style.glowRadius * Metrics.displayPaddingMultiplier
        let expansionPadding = max(style.longSyllableExpansionPadding, 0)
        return EdgeInsets(
            top: padding + max(style.playedRise, 0) + expansionPadding,
            leading: padding + expansionPadding,
            bottom: padding + expansionPadding,
            trailing:
                padding
                + expansionPadding
                + max(layoutConfiguration.trailingVisualOverflow, 0)
        )
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        PerformanceTracer.shared.measure(.lyricsRender) {
            drawTraced(layout: layout, in: &context)
        }
    }

    private func drawTraced(layout: Text.Layout, in context: inout GraphicsContext) {
        let effectsStrength = effectiveTimingEffectsStrength
        if layoutConfiguration.centersLines {
            context.translateBy(x: -displayPadding.leading, y: 0)
        }

        let fittingScale = LyricLineFitting.fittingScale(
            for: layout,
            constrainedWidth: layoutConfiguration.constrainedWidth,
            trailingSafety: style.longSyllableExpansionPadding
        )

        for line in layout {
            var lineContext = context
            let revealMask = effectsStrength > 0
                ? PerformanceTracer.shared.measure(.revealMask) {
                    lineRevealMask(for: line)
                }
                : nil
            if let transform = LyricLineFitting.drawingTransform(
                for: line,
                scale: fittingScale,
                centersLine: layoutConfiguration.centersLines
            ) {
                lineContext.addFilter(
                    .projectionTransform(ProjectionTransform(transform))
                )
            }

            for run in line {
                let horizontalOffset =
                    run[LyricRubyPlacementTextAttribute.self]?
                        .horizontalOffset ?? 0
                var runContext = lineContext
                if horizontalOffset != 0 {
                    runContext.translateBy(
                        x: horizontalOffset,
                        y: 0
                    )
                }
                if effectsStrength > 0 {
                    PerformanceTracer.shared.measure(.glyphDraw) {
                        draw(
                            run,
                            revealMask:
                                revealMask?.offsetBy(
                                    dx: -horizontalOffset
                                ),
                            effectsStrength: effectsStrength,
                            in: &runContext
                        )
                    }
                } else {
                    runContext.draw(run)
                }
            }
        }
    }

    private func lineRevealMask(
        for line: Text.Layout.Line
    ) -> LineRevealMask? {
        let timedRuns = line.compactMap { run -> TimedRun? in
            guard let timing = run[LyricTimingTextAttribute.self],
                  !timing.isWhitespace else {
                return nil
            }
            let horizontalOffset =
                run[LyricRubyPlacementTextAttribute.self]?
                    .horizontalOffset ?? 0
            let bounds = run.typographicBounds.rect.offsetBy(
                dx: horizontalOffset,
                dy: 0
            )
            guard bounds.width.isFinite,
                  bounds.width > 0 else {
                return nil
            }
            return TimedRun(
                timing: timing,
                bounds: bounds,
                layoutDirection: run.layoutDirection
            )
        }
        guard let firstRun = timedRuns.min(
            by: { $0.timing.startTime < $1.timing.startTime }
        ),
        playbackTime >= firstRun.timing.startTime else {
            return nil
        }

        let activeRun = timedRuns.first {
            playbackTime >= $0.timing.startTime
                && playbackTime < $0.timing.endTime
        }
        let completedRun = timedRuns
            .filter { playbackTime >= $0.timing.endTime }
            .max { $0.timing.endTime < $1.timing.endTime }
        let referenceRun = activeRun ?? completedRun ?? firstRun
        let direction = referenceRun.layoutDirection
        let frontX: CGFloat

        if let activeRun {
            let progress = LyricHighlightRevealProgress.progress(
                playbackTime: playbackTime,
                timing: activeRun.timing,
                detectionMode: style.longSyllableDetectionMode,
                durationThreshold: style.longSyllableDurationThreshold
            )
            if direction == .rightToLeft {
                frontX = activeRun.bounds.maxX
                    - activeRun.bounds.width * CGFloat(progress)
            } else {
                frontX = activeRun.bounds.minX
                    + activeRun.bounds.width * CGFloat(progress)
            }
        } else if direction == .rightToLeft {
            frontX = referenceRun.bounds.minX
        } else {
            frontX = referenceRun.bounds.maxX
        }

        let averageGlyphWidth = timedRuns.reduce(CGFloat.zero) {
            $0 + $1.bounds.width
        } / CGFloat(max(timedRuns.count, 1))
        let gradientWidth = style.highlightGradientWidth.isFinite
            ? max(style.highlightGradientWidth, 0.1)
            : Metrics.defaultHighlightGradientWidth
        let gradientReduction = style.highlightGradientReduction.isFinite
            ? min(max(style.highlightGradientReduction, 0), 1)
            : Metrics.defaultHighlightGradientReduction
        return LineRevealMask(
            frontX: frontX,
            featherWidth: max(
                averageGlyphWidth * gradientWidth,
                Metrics.minimumRevealFeatherWidth
            ),
            gradient: highlightGradient(
                reduction: Double(gradientReduction),
                layoutDirection: direction
            ),
            layoutDirection: direction
        )
    }

    private func highlightGradient(
        reduction: Double,
        layoutDirection: LayoutDirection
    ) -> Gradient {
        let reduction = min(max(reduction, 0), 1)
        let stopCount = Metrics.highlightGradientStopCount
        let stops = (0...stopCount).map { index in
            let location = Double(index) / Double(stopCount)
            let distanceFromFront = layoutDirection == .rightToLeft
                ? 1 - location
                : location
            let remainingHighlight = 1 - distanceFromFront
            let opacity = remainingHighlight
                * (1 - reduction * distanceFromFront)

            return Gradient.Stop(
                color: .white.opacity(opacity),
                location: CGFloat(location)
            )
        }
        return Gradient(stops: stops)
    }

    private func draw(
        _ run: Text.Layout.Run,
        revealMask: LineRevealMask?,
        effectsStrength: Double,
        in context: inout GraphicsContext
    ) {
        guard let timing = run[LyricTimingTextAttribute.self] else {
            context.draw(run)
            return
        }

        let state = visualState(for: timing)
        let bounds = run.typographicBounds.rect
        var runContext = context

        let expansionScale: CGFloat
        let expansionOffset: CGSize
        if let glyph = state.amll {
            let em = style.emSize
            let strength = CGFloat(effectsStrength)
            expansionScale = 1 + (CGFloat(glyph.scale) - 1) * strength
            let horizontal = CGFloat(glyph.offsetXEm) * em * strength
            expansionOffset = CGSize(
                width: run.layoutDirection == .rightToLeft ? -horizontal : horizontal,
                height: CGFloat(glyph.offsetYEm + glyph.floatEm) * em * strength
            )
        } else {
            applyLift(
                to: &runContext,
                progress: state.liftProgress,
                effectsStrength: effectsStrength
            )
            expansionScale =
                1
                + (state.expansionScale - 1)
                    * CGFloat(effectsStrength)
            let rawExpansionOffset = self.expansionOffset(
                layoutDirection: run.layoutDirection,
                bounds: bounds,
                emphasis: state.emphasis
            )
            expansionOffset = CGSize(
                width:
                    rawExpansionOffset.width
                    * CGFloat(effectsStrength),
                height:
                    rawExpansionOffset.height
                    * CGFloat(effectsStrength)
            )
        }
        if expansionScale != 1 || expansionOffset != .zero {
            applyExpansion(
                to: &runContext,
                scale: expansionScale,
                anchor: CGPoint(x: bounds.midX, y: bounds.midY),
                offset: expansionOffset
            )
        }

        drawUnplayed(
            run,
            blurRadius:
                state.unplayedBlurRadius
                * CGFloat(effectsStrength),
            effectsStrength: effectsStrength,
            in: &runContext
        )
        guard let revealMask else { return }

        guard revealMask.touches(bounds) else { return }

        drawPlayed(
            run,
            revealMask: revealMask,
            glowStrength:
                state.glowStrength * effectsStrength,
            glowRadius: state.amll.map { CGFloat($0.glowRadiusEm) * style.emSize },
            in: &runContext
        )
    }

    private func amllVisualState(
        for timing: LyricTimingTextAttribute
    ) -> RunVisualState {
        let wordDuration = max(timing.wordEndTime - timing.wordStartTime, 0)
        let count = max(timing.wordCharacterCount, 1)

        var glyph = AMLLWordEmphasis.GlyphState.neutral
        if !timing.isWhitespace,
           AMLLWordEmphasis.shouldEmphasize(
               duration: wordDuration,
               characterCount: count,
               isCJK: !timing.usesWordTimingForLongTone && count == 1
           ) {
            let amounts = AMLLWordEmphasis.amounts(
                duration: wordDuration,
                isLastWordOfLine: timing.isLastWordInLine
            )
            glyph = AMLLWordEmphasis.glyphState(
                playbackTime: playbackTime,
                wordStartTime: timing.wordStartTime,
                index: timing.wordCharacterIndex,
                count: count,
                amounts: amounts
            )
        }

        let baseFloat = AMLLWordEmphasis.baseFloatEm(
            playbackTime: playbackTime,
            wordStartTime: timing.wordStartTime,
            wordEndTime: timing.wordEndTime
        )
        let combined = AMLLWordEmphasis.GlyphState(
            scale: glyph.scale,
            offsetXEm: glyph.offsetXEm,
            offsetYEm: glyph.offsetYEm,
            glowAlpha: glyph.glowAlpha,
            glowRadiusEm: glyph.glowRadiusEm,
            floatEm: glyph.floatEm + baseFloat
        )

        return RunVisualState(
            liftProgress: 0,
            expansionScale: 1,
            emphasis: .inactive,
            unplayedBlurRadius: unplayedBlurRadius(for: timing),
            glowStrength: combined.glowAlpha,
            amll: combined
        )
    }

    private func visualState(
        for timing: LyricTimingTextAttribute
    ) -> RunVisualState {
        if style.usesAMLLEmphasis {
            return amllVisualState(for: timing)
        }
        let rawProgress = playedProgress(for: timing)
        let emphasis = LyricLongToneEmphasis.state(
            playbackTime: playbackTime,
            timing: timing,
            detectionMode: style.longSyllableDetectionMode,
            durationThreshold: style.longSyllableDurationThreshold
        )
        let glowStrength: Double
        if style.drawsGlow, emphasis.isLongTone {
            glowStrength = emphasis.envelope * emphasis.glowAmount
        } else if style.drawsGlow,
                  !style.glowsLongSyllablesOnly,
                  rawProgress > 0 {
            glowStrength = ordinaryGlowStrength(
                for: timing,
                rawProgress: rawProgress
            )
        } else {
            glowStrength = 0
        }

        return RunVisualState(
            liftProgress: liftProgress(for: timing),
            expansionScale: 1
                + (max(style.maximumLongSyllableScale, 1) - 1)
                    * CGFloat(
                        emphasis.envelope
                            * emphasis.expansionAmount
                    ),
            emphasis: emphasis,
            unplayedBlurRadius: unplayedBlurRadius(for: timing),
            glowStrength: glowStrength
        )
    }

    private func liftProgress(
        for timing: LyricTimingTextAttribute
    ) -> Double {
        let liftStartTime = style.liftMode == .word
            ? timing.wordStartTime
            : timing.startTime
        let liftEndTime = style.liftMode == .word
            ? timing.wordEndTime
            : timing.endTime
        guard playbackTime > liftStartTime else { return 0 }

        let transitionEndTime = liftEndTime
            + Metrics.liftContinuationDuration
        let transitionDuration = transitionEndTime - liftStartTime
        guard transitionDuration > 0 else { return 1 }
        return smootherStep(
            (playbackTime - liftStartTime) / transitionDuration
        )
    }

    private func expansionOffset(
        layoutDirection: LayoutDirection,
        bounds: CGRect,
        emphasis: LyricLongToneEmphasis.State
    ) -> CGSize {
        emphasis.expansionOffset(
            layoutDirection: layoutDirection,
            glyphBounds: bounds
        )
    }

    private func drawUnplayed(
        _ run: Text.Layout.Run,
        blurRadius: CGFloat,
        effectsStrength: Double,
        in context: inout GraphicsContext
    ) {
        var unplayedContext = context
        let unplayedOpacity = min(
            max(style.unplayedOpacity, 0),
            1
        )
        unplayedContext.opacity =
            1
            - (1 - unplayedOpacity) * effectsStrength
        if blurRadius > 0 {
            unplayedContext.addFilter(.blur(radius: blurRadius))
        }
        unplayedContext.draw(run)
    }

    private func drawPlayed(
        _ run: Text.Layout.Run,
        revealMask: LineRevealMask,
        glowStrength: Double,
        glowRadius: CGFloat? = nil,
        in context: inout GraphicsContext
    ) {
        guard glowStrength > 0 else {
            var textContext = context
            drawRevealed(run, revealMask: revealMask, in: &textContext)
            return
        }

        context.drawLayer { layer in
            drawGlow(
                for: run,
                revealMask: revealMask,
                strength: glowStrength,
                radius: glowRadius,
                in: &layer
            )

            var textContext = layer
            drawRevealed(
                run,
                revealMask: revealMask,
                in: &textContext
            )
        }
    }

    private func applyLift(
        to context: inout GraphicsContext,
        progress: Double,
        effectsStrength: Double
    ) {
        let verticalOffset =
            liftOffset(at: progress)
            * CGFloat(effectsStrength)
        guard verticalOffset != 0 else { return }
        context.addFilter(
            .projectionTransform(
                ProjectionTransform(
                    CGAffineTransform(
                        translationX: 0,
                        y: verticalOffset
                    )
                )
            )
        )
    }

    private func applyExpansion(
        to context: inout GraphicsContext,
        scale: CGFloat,
        anchor: CGPoint,
        offset: CGSize
    ) {
        let scale = max(scale, 1)
        guard scale != 1 || offset != .zero else { return }
        context.addFilter(
            .projectionTransform(
                ProjectionTransform(
                    CGAffineTransform(
                        a: scale,
                        b: 0,
                        c: 0,
                        d: scale,
                        tx: anchor.x * (1 - scale) + offset.width,
                        ty: anchor.y * (1 - scale) + offset.height
                    )
                )
            )
        )
    }

    private func liftOffset(
        at progress: Double
    ) -> CGFloat {
        -max(style.playedRise, 0)
            * CGFloat(unitProgress(progress))
    }

    private func drawGlow(
        for run: Text.Layout.Run,
        revealMask: LineRevealMask,
        strength: Double,
        radius: CGFloat? = nil,
        in context: inout GraphicsContext
    ) {
        if let radius {
            guard radius > 0 else { return }
            drawGlowLayer(
                for: run,
                revealMask: revealMask,
                radius: radius,
                opacity: min(strength, 1),
                in: &context
            )
            return
        }

        let baseOpacity = style.glowOpacity * strength

        drawGlowLayer(
            for: run,
            revealMask: revealMask,
            radius: style.glowRadius
                * Metrics.outerGlowRadiusMultiplier,
            opacity: min(baseOpacity * Metrics.outerGlowOpacityMultiplier, 1),
            in: &context
        )
        drawGlowLayer(
            for: run,
            revealMask: revealMask,
            radius: style.glowRadius
                * Metrics.innerGlowRadiusMultiplier,
            opacity: min(baseOpacity, 1),
            in: &context
        )
    }

    private func drawGlowLayer(
        for run: Text.Layout.Run,
        revealMask: LineRevealMask,
        radius: CGFloat,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        guard radius > 0, opacity > 0 else { return }

        var glowContext = context
        glowContext.opacity = opacity
        glowContext.blendMode = .plusLighter
        glowContext.addFilter(.blur(radius: radius))
        glowContext.drawLayer { layer in
            drawRevealed(
                run,
                revealMask: revealMask,
                in: &layer
            )
        }
    }

    private func drawRevealed(
        _ run: Text.Layout.Run,
        revealMask: LineRevealMask,
        in context: inout GraphicsContext
    ) {
        let bounds = run.typographicBounds.rect
        guard bounds.width > 0, bounds.height > 0 else { return }

        if revealMask.layoutDirection == .leftToRight,
           bounds.maxX <= revealMask.frontX {
            context.draw(run)
            return
        }

        let startPoint: CGPoint
        let endPoint: CGPoint

        if revealMask.layoutDirection == .rightToLeft {
            startPoint = CGPoint(
                x: revealMask.frontX - revealMask.featherWidth,
                y: bounds.midY
            )
            endPoint = CGPoint(
                x: revealMask.frontX,
                y: bounds.midY
            )
        } else {
            startPoint = CGPoint(
                x: revealMask.frontX,
                y: bounds.midY
            )
            endPoint = CGPoint(
                x: revealMask.frontX + revealMask.featherWidth,
                y: bounds.midY
            )
        }

        context.clipToLayer { maskContext in
            maskContext.fill(
                Path(bounds),
                with: .linearGradient(
                    revealMask.gradient,
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
        }
        context.draw(run)
    }

    private func unplayedBlurRadius(
        for timing: LyricTimingTextAttribute
    ) -> CGFloat {
        guard style.maximumUnplayedBlurRadius > 0,
              playbackTime < timing.startTime else {
            return 0
        }

        let leadTime = timing.startTime - playbackTime
        let distance = smootherStep(
            leadTime / Metrics.unplayedBlurLeadDuration
        )
        let blurFraction = Metrics.minimumUnplayedBlurFraction
            + (1 - Metrics.minimumUnplayedBlurFraction) * distance
        return style.maximumUnplayedBlurRadius * CGFloat(blurFraction)
    }

    private func playedProgress(
        for timing: LyricTimingTextAttribute
    ) -> Double {
        guard playbackTime >= timing.startTime else { return 0 }
        guard playbackTime < timing.endTime else { return 1 }

        let duration = timing.endTime - timing.startTime
        guard duration > 0 else { return 1 }
        return unitProgress((playbackTime - timing.startTime) / duration)
    }

    private func ordinaryGlowStrength(
        for timing: LyricTimingTextAttribute,
        rawProgress: Double
    ) -> Double {
        if playbackTime <= timing.endTime {
            let attack = smootherStep(
                rawProgress / Metrics.glowAttackProgress
            )
            let breath = Metrics.minimumGlowStrength
                + (1 - Metrics.minimumGlowStrength)
                    * sin(.pi * rawProgress)
            return attack
                * breath
                * Metrics.ordinaryGlowStrengthMultiplier
        }

        let tailProgress = (playbackTime - timing.endTime)
            / Self.glowTailDuration
        guard tailProgress < 1 else { return 0 }
        return (1 - smootherStep(tailProgress))
            * Metrics.minimumGlowStrength
            * Metrics.ordinaryGlowStrengthMultiplier
    }

    private func smootherStep(_ value: Double) -> Double {
        let progress = unitProgress(value)
        return progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private func unitProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private var effectiveTimingEffectsStrength: Double {
        guard appliesTimingEffects else { return 0 }
        return unitProgress(timingEffectsStrength)
    }
}

private extension LyricGlowTextRenderer {
    struct TimedRun {
        let timing: LyricTimingTextAttribute
        let bounds: CGRect
        let layoutDirection: LayoutDirection
    }

    struct LineRevealMask {
        let frontX: CGFloat
        let featherWidth: CGFloat
        let gradient: Gradient
        let layoutDirection: LayoutDirection

        func offsetBy(dx: CGFloat) -> Self {
            Self(
                frontX: frontX + dx,
                featherWidth: featherWidth,
                gradient: gradient,
                layoutDirection: layoutDirection
            )
        }

        func touches(_ bounds: CGRect) -> Bool {
            guard layoutDirection == .leftToRight else { return true }
            return bounds.minX < frontX + featherWidth
        }
    }

    struct RunVisualState {
        let liftProgress: Double
        let expansionScale: CGFloat
        let emphasis: LyricLongToneEmphasis.State
        let unplayedBlurRadius: CGFloat
        let glowStrength: Double
        var amll: AMLLWordEmphasis.GlyphState?
    }

    enum Metrics {
        static let displayPaddingMultiplier: CGFloat = 6
        static let unplayedBlurLeadDuration: TimeInterval = 2.4
        static let minimumUnplayedBlurFraction = 0.12
        static let glowAttackProgress = 0.24
        static let minimumGlowStrength = 0.82
        static let ordinaryGlowStrengthMultiplier = 0.55
        static let liftContinuationDuration: TimeInterval = 0.32
        static let outerGlowRadiusMultiplier: CGFloat = 1
        static let outerGlowOpacityMultiplier = 0.55
        static let innerGlowRadiusMultiplier: CGFloat = 0.35
        static let defaultHighlightGradientWidth: CGFloat = 0.7
        static let defaultHighlightGradientReduction: CGFloat = 0.65
        static let highlightGradientStopCount = 8
        static let minimumRevealFeatherWidth: CGFloat = 2
    }
}
