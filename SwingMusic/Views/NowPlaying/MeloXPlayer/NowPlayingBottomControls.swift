import SwiftUI

struct NowPlayingBottomControls: View {
    static let utilityHeight: CGFloat = 62
    static let coreHeight: CGFloat = 279
    static let overlayHeight = utilityHeight + coreHeight

    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let song: Song
    @Binding var page: NowPlayingPage
    let showsLyricsUtilities: Bool
    let hasLyricsTranslations: Bool
    let hasLyricsRomanizations: Bool
    let isInterfaceHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingLyricsUtilityControls(
                isVisible:
                    showsLyricsUtilities
                    && !isInterfaceHidden,
                hasTranslations: hasLyricsTranslations,
                hasRomanizations: hasLyricsRomanizations
            )
            .frame(height: Self.utilityHeight, alignment: .top)

            coreControls
        }
        .frame(height: Self.overlayHeight)
    }

    private var coreControls: some View {
        VStack(spacing: 0) {
            interfaceLayer(.progress) {
                NowPlayingProgressControl(song: song)
            }

            Color.clear
                .frame(height: 19)

            interfaceLayer(.transport) {
                NowPlayingTransportControls()
            }

            Color.clear
                .frame(height: 31)

            interfaceLayer(.volume) {
                NowPlayingVolumeControl()
            }

            Color.clear
                .frame(height: 3)

            interfaceLayer(.pageSelector) {
                NowPlayingPageSelector(page: $page)
            }
        }
        .frame(height: Self.coreHeight)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {}
        }
    }

    private func interfaceLayer<Content: View>(
        _ layer: NowPlayingInterfaceTransition.ControlLayer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(
                y: isInterfaceHidden
                    ? NowPlayingInterfaceTransition.hiddenOffset(
                        for: layer
                    )
                    : 0
            )
            .opacity(isInterfaceHidden ? 0 : 1)
            .animation(
                NowPlayingInterfaceTransition.controlAnimation(
                    for: layer,
                    isVisible: !isInterfaceHidden,
                    reducesMotion: accessibilityReduceMotion
                ),
                value: isInterfaceHidden
            )
    }
}

private struct NowPlayingLyricsUtilityControls: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let isVisible: Bool
    let hasTranslations: Bool
    let hasRomanizations: Bool

    var body: some View {
        HStack {
            if hasTranslations || hasRomanizations {
                NowPlayingLyricsLanguageButton(
                    hasTranslations: hasTranslations,
                    hasRomanizations: hasRomanizations
                )
                    .scaleEffect(
                        isVisible
                            ? 1
                            : NowPlayingInterfaceTransition
                                .utilityHiddenScale
                    )
            }

            Spacer()
        }
        .offset(
            y: isVisible
                ? 0
                : NowPlayingInterfaceTransition
                    .utilityHiddenOffset
        )
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(
            NowPlayingInterfaceTransition.utilityAnimation(
                isVisible: isVisible,
                reducesMotion: accessibilityReduceMotion
            ),
            value: isVisible
        )
    }
}
