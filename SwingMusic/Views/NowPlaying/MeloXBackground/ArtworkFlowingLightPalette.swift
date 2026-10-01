import Foundation

struct ArtworkFlowingLightPalette: Equatable, Sendable {
    nonisolated static let gridDimension = 3
    nonisolated static let fallback = Self(
        colorsRGB: fallbackColors
    )

    let colorsRGB: [SIMD3<Double>]

    nonisolated init(colorsRGB: [SIMD3<Double>]) {
        let expectedCount =
            Self.gridDimension * Self.gridDimension
        self.colorsRGB = colorsRGB.count == expectedCount
            ? colorsRGB
            : Self.fallbackColors
    }

    nonisolated var displayColorsRGB: [SIMD3<Double>] {
        let sourceColors = colorsRGB.map(FlowingLightHSV.init)
        let anchor =
            sourceColors.max {
                vividness(of: $0)
                    < vividness(of: $1)
            }
            ?? FlowingLightHSV(
                hue: 0.62,
                saturation: 0.72,
                value: 0.48
            )
        let averageValue =
            sourceColors
                .map(\.value)
                .reduce(0, +)
                / Double(sourceColors.count)
        let chromaticStrength = clamped(
            anchor.saturation / 0.34,
            lowerBound: 0,
            upperBound: 1
        )

        let targetValues = [
            0.34, 0.46, 0.28,
            0.27, 0.50, 0.36,
            0.17, 0.30, 0.15,
        ]
        let targetSaturations = [
            0.76, 0.64, 0.82,
            0.84, 0.66, 0.78,
            0.90, 0.80, 0.92,
        ]

        return sourceColors.indices.map { index in
            let source = sourceColors[index]
            let usesSourceHue =
                source.saturation >= 0.16
                    && source.value >= 0.08
            let hue = usesSourceHue
                ? blendedHue(
                    anchor.hue,
                    source.hue,
                    destinationWeight: 0.62
                )
                : anchor.hue
            let artworkSaturation =
                source.saturation * 0.58
                    + anchor.saturation * 0.42
            let roleSaturation =
                0.16
                    + (
                        targetSaturations[index]
                            - 0.16
                    ) * chromaticStrength
            let saturation = clamped(
                max(
                    roleSaturation,
                    artworkSaturation
                ),
                lowerBound: 0.12,
                upperBound: 0.96
            )
            let sourceValueOffset =
                clamped(
                    source.value - averageValue,
                    lowerBound: -0.12,
                    upperBound: 0.12
                ) * 0.24
            let value = clamped(
                targetValues[index]
                    + sourceValueOffset,
                lowerBound: 0.12,
                upperBound: 0.54
            )
            return FlowingLightHSV(
                hue: hue,
                saturation: saturation,
                value: value
            ).rgb
        }
    }

    nonisolated var luminousRGB: SIMD3<Double> {
        let anchor =
            colorsRGB
                .map(FlowingLightHSV.init)
                .max {
                    vividness(of: $0)
                        < vividness(of: $1)
                }
            ?? FlowingLightHSV(
                hue: 0.62,
                saturation: 0.72,
                value: 0.48
            )
        return FlowingLightHSV(
            hue: anchor.hue,
            saturation:
                anchor.saturation >= 0.12
                    ? max(anchor.saturation, 0.68)
                    : 0.12,
            value: 0.90
        ).rgb
    }

    private nonisolated func vividness(
        of color: FlowingLightHSV
    ) -> Double {
        color.saturation
            * (0.38 + color.value * 0.62)
    }

    private nonisolated func blendedHue(
        _ source: Double,
        _ destination: Double,
        destinationWeight: Double
    ) -> Double {
        var delta = destination - source
        if delta > 0.5 {
            delta -= 1
        } else if delta < -0.5 {
            delta += 1
        }

        let blended =
            source + delta * destinationWeight
        if blended < 0 {
            return blended + 1
        }
        if blended >= 1 {
            return blended - 1
        }
        return blended
    }

    private nonisolated func clamped(
        _ value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        min(max(value, lowerBound), upperBound)
    }

    private nonisolated static let fallbackColors: [SIMD3<Double>] = [
        SIMD3(0.08, 0.12, 0.24),
        SIMD3(0.18, 0.10, 0.34),
        SIMD3(0.06, 0.23, 0.30),
        SIMD3(0.22, 0.08, 0.24),
        SIMD3(0.14, 0.28, 0.42),
        SIMD3(0.30, 0.12, 0.30),
        SIMD3(0.05, 0.18, 0.26),
        SIMD3(0.16, 0.10, 0.30),
        SIMD3(0.07, 0.11, 0.20),
    ]
}

private nonisolated struct FlowingLightHSV: Sendable {
    let hue: Double
    let saturation: Double
    let value: Double

    init(_ rgb: SIMD3<Double>) {
        let red = min(max(rgb.x, 0), 1)
        let green = min(max(rgb.y, 0), 1)
        let blue = min(max(rgb.z, 0), 1)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        value = maximum
        saturation =
            maximum > 0
                ? delta / maximum
                : 0

        guard delta > 0 else {
            hue = 0
            return
        }

        let rawHue: Double
        if maximum == red {
            rawHue =
                ((green - blue) / delta)
                    .truncatingRemainder(
                        dividingBy: 6
                    )
        } else if maximum == green {
            rawHue =
                (blue - red) / delta + 2
        } else {
            rawHue =
                (red - green) / delta + 4
        }
        let normalizedHue = rawHue / 6
        hue =
            normalizedHue >= 0
                ? normalizedHue
                : normalizedHue + 1
    }

    init(
        hue: Double,
        saturation: Double,
        value: Double
    ) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }

    var rgb: SIMD3<Double> {
        let chroma = value * saturation
        let hueSector = hue * 6
        let secondary =
            chroma
                * (
                    1
                        - abs(
                            hueSector
                                .truncatingRemainder(
                                    dividingBy: 2
                                )
                                - 1
                        )
                )
        let offset = value - chroma
        let base: SIMD3<Double>

        switch hueSector {
        case 0..<1:
            base = SIMD3(chroma, secondary, 0)
        case 1..<2:
            base = SIMD3(secondary, chroma, 0)
        case 2..<3:
            base = SIMD3(0, chroma, secondary)
        case 3..<4:
            base = SIMD3(0, secondary, chroma)
        case 4..<5:
            base = SIMD3(secondary, 0, chroma)
        default:
            base = SIMD3(chroma, 0, secondary)
        }

        return base + SIMD3<Double>(repeating: offset)
    }
}
