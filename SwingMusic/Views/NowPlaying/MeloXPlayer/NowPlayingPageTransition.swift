import SwiftUI

enum NowPlayingPageTransition {
    static let animation = Animation.smooth(duration: 0.3)
    static let directLyricsQueueContentScale: CGFloat = 0.92
    static let lyricsEntranceOffset: CGFloat = 400
    static let queueOffset: CGFloat = 400
    static let lyricsEntranceDelay = Duration.milliseconds(110)
    static let lyricsExitInterruptionWindow =
        Duration.milliseconds(240)
    static let lyricsEntranceAnimation =
        Animation.smooth(duration: 0.34)
    private static let directLyricsQueueAnimation =
        Animation.smooth(duration: 0.44)

    private static let artworkDetailsInsertionOffset: CGFloat = -300
    private static let artworkDetailsRemovalOffset: CGFloat = -300
    private static let songHeaderOffset: CGFloat = 40
    private static let outgoingAnimation =
        Animation.smooth(duration: 0.24)
    private static let incomingAnimation =
        Animation.smooth(duration: 0.22).delay(0.07)
    private static let delayedResidentPageEntranceAnimation =
        Animation.smooth(duration: 0.34).delay(0.11)

    static func content(
        for page: NowPlayingPage,
        entersFromHiddenQueue: Bool,
        reducesMotion: Bool
    ) -> AnyTransition {
        if reducesMotion {
            return .opacity
        }

        if entersFromHiddenQueue {
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        }

        switch page {
        case .artwork:
            return directionalOffsetAndOpacity(
                insertionY: artworkDetailsInsertionOffset,
                removalY: artworkDetailsRemovalOffset
            )
        case .lyrics:
            return .asymmetric(
                insertion: .identity,
                removal:
                    offsetAndOpacity(y: lyricsEntranceOffset)
                    .animation(outgoingAnimation)
            )
        case .queue:
            return stagedOffsetAndOpacity(y: queueOffset)
        }
    }

    static func songHeader(reducesMotion: Bool) -> AnyTransition {
        guard !reducesMotion else { return .opacity }
        return stagedOffsetAndOpacity(y: songHeaderOffset)
    }

    static func selectionAnimation(
        from source: NowPlayingPage,
        to destination: NowPlayingPage
    ) -> Animation {
        if isDirectLyricsQueueTransition(
            from: source,
            to: destination
        ) {
            return directLyricsQueueAnimation
        }
        return animation
    }

    static func residentQueueAnimation(
        from source: NowPlayingPage,
        to destination: NowPlayingPage,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        if isDirectLyricsQueueTransition(
            from: source,
            to: destination
        ) {
            return directLyricsQueueAnimation
        }
        if destination == .queue {
            return delayedResidentPageEntranceAnimation
        }
        if source == .queue {
            return outgoingAnimation
        }
        return nil
    }

    static func residentLyricsAnimation(
        from source: NowPlayingPage,
        to destination: NowPlayingPage,
        interruptsExit: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        if isDirectLyricsQueueTransition(
            from: source,
            to: destination
        ) {
            return directLyricsQueueAnimation
        }
        if source == .lyrics {
            return outgoingAnimation
        }
        if source == .artwork,
           destination == .lyrics,
           interruptsExit {
            return lyricsEntranceAnimation
        }
        return nil
    }

    static func isDirectLyricsQueueTransition(
        from source: NowPlayingPage,
        to destination: NowPlayingPage
    ) -> Bool {
        source == .lyrics && destination == .queue
            || source == .queue && destination == .lyrics
    }

    static func directAlternateContent(
        reducesMotion: Bool
    ) -> AnyTransition {
        guard !reducesMotion else { return .opacity }
        return .scale(
            scale: directLyricsQueueContentScale,
            anchor: .center
        )
        .combined(with: .opacity)
    }

    private static func stagedOffsetAndOpacity(
        y: CGFloat
    ) -> AnyTransition {
        directionalOffsetAndOpacity(
            insertionY: y,
            removalY: y
        )
    }

    private static func directionalOffsetAndOpacity(
        insertionY: CGFloat,
        removalY: CGFloat
    ) -> AnyTransition {
        .asymmetric(
            insertion:
                offsetAndOpacity(y: insertionY)
                .animation(incomingAnimation),
            removal:
                offsetAndOpacity(y: removalY)
                .animation(outgoingAnimation)
        )
    }

    private static func offsetAndOpacity(
        y: CGFloat
    ) -> AnyTransition {
        .offset(y: y).combined(with: .opacity)
    }
}
