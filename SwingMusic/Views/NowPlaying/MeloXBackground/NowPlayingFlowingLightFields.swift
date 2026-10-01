import SwiftUI

struct NowPlayingFlowingLightFields: View {
    let primaryCenter: UnitPoint
    let secondaryCenter: UnitPoint
    let shadowCenter: UnitPoint
    let luminousColor: Color
    let secondaryColor: Color
    let expansion: Double

    var body: some View {
        GeometryReader { proxy in
            let radius = max(
                proxy.size.width,
                proxy.size.height
            )

            ZStack {
                primaryLight(radius: radius)
                secondaryLight(radius: radius)
                movingShadow(radius: radius)
            }
        }
    }

    private func primaryLight(
        radius: CGFloat
    ) -> some View {
        RadialGradient(
            stops: [
                .init(
                    color:
                        luminousColor
                            .opacity(0.48),
                    location: 0
                ),
                .init(
                    color:
                        luminousColor
                            .opacity(0.18),
                    location: 0.28
                ),
                .init(
                    color:
                        luminousColor
                            .opacity(0.07),
                    location: 0.60
                ),
                .init(
                    color: .clear,
                    location: 0.86
                ),
                .init(
                    color: .clear,
                    location: 1
                ),
            ],
            center: primaryCenter,
            startRadius: 0,
            endRadius:
                radius * 0.92 * expansion
        )
        .blendMode(.screen)
        .opacity(0.28)
    }

    private func secondaryLight(
        radius: CGFloat
    ) -> some View {
        RadialGradient(
            stops: [
                .init(
                    color: .white.opacity(0.14),
                    location: 0
                ),
                .init(
                    color:
                        secondaryColor
                            .opacity(0.13),
                    location: 0.30
                ),
                .init(
                    color:
                        secondaryColor
                            .opacity(0.04),
                    location: 0.62
                ),
                .init(
                    color: .clear,
                    location: 0.88
                ),
                .init(
                    color: .clear,
                    location: 1
                ),
            ],
            center: secondaryCenter,
            startRadius: 0,
            endRadius:
                radius
                    * 0.82
                    * (
                        1
                            + (expansion - 1)
                                * 0.55
                    )
        )
        .blendMode(.screen)
        .opacity(0.22)
    }

    private func movingShadow(
        radius: CGFloat
    ) -> some View {
        RadialGradient(
            stops: [
                .init(
                    color: .black.opacity(0.56),
                    location: 0
                ),
                .init(
                    color: .black.opacity(0.17),
                    location: 0.34
                ),
                .init(
                    color: .black.opacity(0.04),
                    location: 0.66
                ),
                .init(
                    color: .clear,
                    location: 0.88
                ),
                .init(
                    color: .clear,
                    location: 1
                ),
            ],
            center: shadowCenter,
            startRadius: 0,
            endRadius: radius * 0.78
        )
        .blendMode(.multiply)
        .opacity(0.32)
    }
}
