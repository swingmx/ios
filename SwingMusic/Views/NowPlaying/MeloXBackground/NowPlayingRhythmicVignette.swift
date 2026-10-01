import SwiftUI

struct NowPlayingRhythmicVignette: View {
    let pulse: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedPulse = min(
                max(pulse, 0),
                1
            )
            let radius = hypot(
                proxy.size.width,
                proxy.size.height
            ) * 0.50

            RadialGradient(
                stops: [
                    .init(
                        color: .clear,
                        location: 0
                    ),
                    .init(
                        color:
                            .black.opacity(
                                0.02
                                    + clampedPulse
                                        * 0.05
                            ),
                        location:
                            0.52
                                - clampedPulse
                                    * 0.04
                    ),
                    .init(
                        color:
                            .black.opacity(
                                0.12
                                    + clampedPulse
                                        * 0.15
                            ),
                        location:
                            0.78
                                - clampedPulse
                                    * 0.07
                    ),
                    .init(
                        color:
                            .black.opacity(
                                0.27
                                    + clampedPulse
                                        * 0.24
                            ),
                        location: 1
                    ),
                ],
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
        }
    }
}
