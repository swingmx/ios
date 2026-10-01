import Foundation

nonisolated struct FlowingLightMotionField: Sendable {
    private let seed: UInt64

    init(songID: Int) {
        seed = UInt64(
            bitPattern: Int64(songID)
        )
    }

    func value(
        at phase: Double,
        channel: Int
    ) -> Double {
        let firstFrequency =
            0.42 + random(channel * 7) * 0.24
        let secondFrequency =
            0.83 + random(channel * 7 + 1) * 0.38
        let thirdFrequency =
            1.37 + random(channel * 7 + 2) * 0.54
        let firstPhase =
            random(channel * 7 + 3) * .pi * 2
        let secondPhase =
            random(channel * 7 + 4) * .pi * 2
        let thirdPhase =
            random(channel * 7 + 5) * .pi * 2

        return sin(
            phase * firstFrequency + firstPhase
        ) * 0.54
            + sin(
                phase * secondFrequency + secondPhase
            ) * 0.29
            + cos(
                phase * thirdFrequency + thirdPhase
            ) * 0.17
    }

    private func random(_ channel: Int) -> Double {
        var value =
            seed
                &+ UInt64(
                    truncatingIfNeeded: channel
                )
                &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30))
            &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27))
            &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(
            value & 0x001F_FFFF_FFFF_FFFF
        ) / Double(0x001F_FFFF_FFFF_FFFF)
    }
}
