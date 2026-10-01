import SwiftUI

enum NowPlayingInterfaceTransition {
    enum ControlLayer {
        case progress
        case transport
        case volume
        case pageSelector
    }

    static let utilityHiddenOffset: CGFloat = 64
    static let utilityHiddenScale: CGFloat = 0.82

    private static let coreShowAnimation =
        Animation.smooth(duration: 0.34)
    private static let coreHideAnimation =
        Animation.smooth(duration: 0.34)
    private static let utilityShowAnimation =
        Animation.smooth(duration: 0.24)
    private static let utilityHideAnimation =
        Animation.smooth(duration: 0.24).delay(0.1)

    static func interfaceAnimation(
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return isVisible
            ? coreShowAnimation
            : coreHideAnimation
    }

    static func utilityAnimation(
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return isVisible
            ? utilityShowAnimation
            : utilityHideAnimation
    }

    static func hiddenOffset(
        for layer: ControlLayer
    ) -> CGFloat {
        switch layer {
        case .progress:
            180
        case .transport:
            165
        case .volume:
            148
        case .pageSelector:
            128
        }
    }

    static func controlAnimation(
        for layer: ControlLayer,
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }

        let delay = isVisible
            ? showDelay(for: layer)
            : hideDelay(for: layer)
        return Animation
            .smooth(duration: 0.24)
            .delay(delay)
    }

    private static func showDelay(
        for layer: ControlLayer
    ) -> TimeInterval {
        switch layer {
        case .progress:
            0.025
        case .transport:
            0.05
        case .volume:
            0.075
        case .pageSelector:
            0.1
        }
    }

    private static func hideDelay(
        for layer: ControlLayer
    ) -> TimeInterval {
        switch layer {
        case .progress:
            0.075
        case .transport:
            0.05
        case .volume:
            0.025
        case .pageSelector:
            0
        }
    }
}
