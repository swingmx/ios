import SwiftUI

enum NowPlayingPage: String, Hashable {
    case artwork
    case lyrics
    case queue
}

struct NowPlayingView: View {
    private static let portraitHorizontalPadding: CGFloat = 32

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled)
    private var accessibilityVoiceOverEnabled
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LyricsStore.self) private var lyricsStore

    @State private var page: NowPlayingPage
    @State private var showsLyricsControls = true
    @State private var appleMusicControlsActivityGeneration = 0
    @State private var highlightedLyricID: MXLyricLine.ID?
    @State private var showsTextPVLandscapeSuggestion = false
    @State private var isQueueSongHeaderHidden = false
    @State private var queueSongHeaderOffset: CGFloat = 0
    @State private var artworkPageFrame = CGRect.zero
    @State private var entersPageFromHiddenQueue = false
    @State private var transitionSourcePage: NowPlayingPage
    @State private var transitionDestinationPage: NowPlayingPage
    @State private var pageTransitionResetGeneration = 0
    @State private var lyricsEntranceState:
        NowPlayingLyricsEntranceState = .presented
    @State private var preparedLyricsSongID: Song.ID?
    @State private var lyricsExitInterruptionDeadline:
        ContinuousClock.Instant?
    @State private var interruptsLyricsExit = false
    @Namespace private var pageArtworkNamespace

    static var debugStartPage: NowPlayingPage = .artwork

    init(initialPage: NowPlayingPage = NowPlayingView.debugStartPage) {
        _page = State(initialValue: initialPage)
        _transitionSourcePage = State(initialValue: initialPage)
        _transitionDestinationPage = State(initialValue: initialPage)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if usesMonochromeLyricsBackground {
                    Color.black
                        .ignoresSafeArea()
                } else {
                    NowPlayingBackground(
                        artworkURL:
                            player.currentSong?.largeArtworkURL,
                        beatTimeline:
                            player.currentBeatTimeline,
                        isMotionPaused: page == .lyrics
                    )
                }

                if let song = player.currentSong {
                    if proxy.size.width > proxy.size.height {
                        NowPlayingLandscapeView(
                            page: pageSelection,
                            showsLyricsControls: showsLyricsControls,
                            song: song,
                            lyrics: lyrics,
                            lyricError: lyricError,
                            highlightedLyricID: highlightedLyricID,
                            artworkNamespace: pageArtworkNamespace,
                            onDismiss: { dismiss() },
                            onInterfaceInteraction: handleLyricsInterfaceInteraction,
                            onInterfaceVisibilityChange: setAppleMusicLyricsControlsVisible,
                            onLyricsContentPrepared: {
                                markLyricsContentPrepared(for: song.id)
                            }
                        )
                        .transition(.opacity)
                    } else {
                        portraitContent(for: song)
                    }
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note")
                        .foregroundStyle(.white)
                }

                if usesFullScreenTextPV,
                   showsTextPVLandscapeSuggestion,
                   proxy.size.width <= proxy.size.height {
                    Label("", systemImage: "rectangle.landscape.rotate")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .safeAreaPadding(.top, 58)
                        .accessibilityLabel("")
                }
            }
        }
        .keepsScreenAwake(keepsPlayerScreenAwake)
        .preferredColorScheme(.dark)
        .task(id: beatAnalysisTaskID) {
            await loadBeatTimeline()
        }
        .task(id: usesFullScreenTextPV) {
            guard usesFullScreenTextPV else {
                showsTextPVLandscapeSuggestion = false
                return
            }

            withAnimation(accessibilityReduceMotion ? nil : .smooth(duration: 0.25)) {
                showsTextPVLandscapeSuggestion = true
            }
            do {
                try await Task.sleep(for: .seconds(3.2))
            } catch {
                return
            }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.2)) {
                showsTextPVLandscapeSuggestion = false
            }
        }
        .task(id: appleMusicControlsActivityGeneration) {
            guard usesAutoHidingAppleMusicInterface,
                  showsLyricsControls,
                  !accessibilityVoiceOverEnabled else {
                return
            }

            do {
                try await Task.sleep(
                    for: .seconds(
                        settings
                            .appleMusicLyricsInterfaceAutoHideDelay
                    )
                )
            } catch {
                return
            }
            guard !Task.isCancelled,
                  usesAutoHidingAppleMusicInterface else {
                return
            }

            withAnimation(
                NowPlayingInterfaceTransition.interfaceAnimation(
                    isVisible: false,
                    reducesMotion: accessibilityReduceMotion
                )
            ) {
                showsLyricsControls = false
            }
        }
        .task(id: entersPageFromHiddenQueue) {
            await restoreArtworkTransitionAfterHiddenQueueEntry()
        }
        .task(id: pageTransitionResetGeneration) {
            await restoreDefaultPageTransition()
        }
        .task(id: lyricsEntranceState) {
            await presentLyricsEntrance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("debugOpenLyrics"))) { _ in
            page = .lyrics
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("debugOpenQueue"))) { _ in
            page = .queue
        }
        .onChange(of: page) { _, newPage in
            if newPage == .queue {
                NotificationCenter.default.post(name: NowPlayingQueuePage.shownNotification, object: nil)
            }
            if newPage == .lyrics,
               settings.lyricsStyle == .appleMusic {
                registerAppleMusicControlsActivity()
            } else {
                cancelAppleMusicControlsAutoHide()
                showsLyricsControls = true
            }

            guard settings.rememberNowPlayingPage else { return }
            settings.rememberedNowPlayingPage = newPage.rawValue
        }
        .onChange(of: accessibilityVoiceOverEnabled) {
            _, voiceOverEnabled in
            guard usesAutoHidingAppleMusicInterface else { return }

            if voiceOverEnabled {
                cancelAppleMusicControlsAutoHide()
                showsLyricsControls = true
            } else {
                registerAppleMusicControlsActivity()
            }
        }
        .onChange(of: settings.lyricsStyle) { _, newStyle in
            cancelAppleMusicControlsAutoHide()
            showsLyricsControls = true

            if page == .lyrics, newStyle == .appleMusic {
                registerAppleMusicControlsActivity()
            }
        }
        .onChange(
            of: settings.appleMusicLyricsInterfaceAutoHideDelay
        ) {
            registerAppleMusicControlsActivity()
        }
        .onAppear {
            resetPodcastPageIfNeeded()
        }
        .onChange(of: player.currentSong?.id) {
            resetPodcastPageIfNeeded()
        }
    }

    private var beatAnalysisTaskID:
        NowPlayingBeatAnalysisTaskID {
        NowPlayingBeatAnalysisTaskID(
            songID: player.currentSong?.id,
            isPlaybackReady: !player.isLoading,
            isEnabled:
                settings.playerBackgroundStyle
                    == .flowingLight
                    && settings
                        .playerBackgroundBeatEffectsEnabled
                    && player.currentSong?.isPodcastProgram != true
        )
    }

    private func loadBeatTimeline() async {
        let taskID = beatAnalysisTaskID
        guard taskID.isEnabled else {
            player.clearCurrentSongBeatAnalysis()
            return
        }
        guard
              taskID.isPlaybackReady,
              taskID.songID != nil else {
            return
        }

        await player.analyzeCurrentSongBeats()
    }

    private func resetPodcastPageIfNeeded() {
        guard player.currentSong?.isPodcastProgram == true,
              page == .lyrics else {
            return
        }
        page = .artwork
        transitionSourcePage = .artwork
        transitionDestinationPage = .artwork
    }

    private func portraitContent(for song: Song) -> some View {
        VStack(spacing: 0) {
            dismissalHandle

            pageContent(for: song)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    portraitPlayerControlsLayer(for: song)
                }
        }
        .padding(.horizontal, Self.portraitHorizontalPadding)
        .safeAreaPadding(.bottom, 3)
    }

    private func portraitPlayerControlsLayer(
        for song: Song
    ) -> some View {
        ZStack(alignment: .bottom) {
            portraitPlayerControls(for: song)
                .allowsHitTesting(!hidesLyricsControls)
                .accessibilityHidden(hidesLyricsControls)

            if hidesLyricsControls,
               settings.lyricsStyle != .appleMusic {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(
                        height: NowPlayingBottomControls.overlayHeight
                    )
                    .contentShape(.rect)
                    .onTapGesture {
                        handleLyricsInterfaceInteraction()
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(height: NowPlayingBottomControls.overlayHeight)
    }

    private func portraitPlayerControls(for song: Song) -> some View {
        NowPlayingBottomControls(
            song: song,
            page: pageSelection,
            showsLyricsUtilities:
                usesExpandedAppleMusicLyricsLayout,
            hasLyricsTranslations: hasLyricsTranslations,
            hasLyricsRomanizations: hasLyricsRomanizations,
            isInterfaceHidden: hidesLyricsControls
        )
    }

    private var pageSelection: Binding<NowPlayingPage> {
        Binding(
            get: { page },
            set: { newPage in
                let previousPage = page
                let startsLyricsEntrance =
                    previousPage == .artwork
                    && newPage == .lyrics
                    && settings.lyricsStyle == .appleMusic
                let interruptsActiveLyricsExit =
                    startsLyricsEntrance
                    && lyricsExitInterruptionDeadline.map {
                        ContinuousClock.now < $0
                    } == true
                transitionSourcePage = previousPage
                transitionDestinationPage = newPage
                pageTransitionResetGeneration &+= 1
                interruptsLyricsExit =
                    interruptsActiveLyricsExit
                entersPageFromHiddenQueue =
                    previousPage == .queue
                    && isQueueSongHeaderHidden
                    && newPage != .queue
                if previousPage == .lyrics,
                   newPage == .artwork {
                    lyricsExitInterruptionDeadline =
                        ContinuousClock.now.advanced(
                            by: NowPlayingPageTransition
                                .lyricsExitInterruptionWindow
                        )
                } else if newPage == .lyrics {
                    lyricsExitInterruptionDeadline = nil
                }
                if startsLyricsEntrance {
                    if interruptsActiveLyricsExit {
                        interruptLyricsExit()
                    } else {
                        beginLyricsEntrance()
                    }
                }
                page = newPage
            }
        )
    }

    private var hidesLyricsControls: Bool {
        page == .lyrics && !showsLyricsControls
    }

    private var usesAutoHidingAppleMusicInterface: Bool {
        page == .lyrics && settings.lyricsStyle == .appleMusic
    }

    private var lyrics: [MXLyricLine] {
        lyricsStore.lyrics
    }

    private var lyricError: String? {
        lyricsStore.errorMessage
    }

    private var hasLyricsTranslations: Bool {
        lyrics.contains { $0.hasTranslation }
    }

    private var hasLyricsRomanizations: Bool {
        lyrics.contains { $0.hasRomanization }
    }

    private var keepsPlayerScreenAwake: Bool {
        switch settings.playerScreenAwakeMode {
        case .disabled:
            false
        case .player:
            true
        case .lyrics:
            page == .lyrics
        case .hiddenLyricsInterface:
            hidesLyricsControls
        }
    }

    private var usesExpandedAppleMusicLyricsLayout: Bool {
        page == .lyrics && settings.lyricsStyle == .appleMusic
    }

    private var usesFullScreenTextPV: Bool {
        page == .lyrics && settings.lyricsStyle == .textPV
    }

    private var usesMonochromeLyricsBackground: Bool {
        page == .lyrics && settings.lyricsStyle.usesMonochromePlayerBackground
    }

    private var dismissalHandle: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.52))
                .frame(width: 60, height: 5)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .contentShape(.rect)
        .onTapGesture {
            dismiss()
        }
        .accessibilityElement()
        .accessibilityLabel("Collapse player")
        .accessibilityHint("Tap to collapse, or drag down")
        .accessibilityAction {
            dismiss()
        }
    }

    private func pageContent(for song: Song) -> some View {
        ZStack(alignment: .top) {
            transientArtworkPageContent(for: song)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()

            residentQueuePage(for: song)

            if settings.lyricsStyle == .appleMusic {
                residentAppleMusicLyricsPage(for: song)
            } else if page == .lyrics {
                portraitLyricsPage(for: song)
                    .clipped()
                    .transition(
                        pageContentTransition(for: .lyrics)
                    )
            }

            if page != .artwork {
                sharedPortraitSongHeader(for: song)
                    .offset(y: sharedPortraitSongHeaderOffset)
                    .clipped()
                    .transition(
                        NowPlayingPageTransition.songHeader(
                            reducesMotion: accessibilityReduceMotion
                        )
                    )
            }

        }
        .overlay {
            GeometryReader { overlayProxy in
                let estimated = Self.estimatedArtworkFrame(in: overlayProxy.size)
                let frame = portraitArtworkFrame.width > 0 ? portraitArtworkFrame : estimated
                if frame.width > 0 {
                    NowPlayingPortraitArtwork(
                        song: song,
                        isArtworkPage: page == .artwork
                    )
                    .frame(
                        width: frame.width,
                        height: frame.height
                    )
                    .contentShape(.rect)
                    .onTapGesture {
                        guard page != .artwork else { return }
                        withAnimation(
                            accessibilityReduceMotion
                                ? nil
                                : NowPlayingPageTransition.selectionAnimation(
                                    from: page,
                                    to: .artwork
                                )
                        ) {
                            page = .artwork
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Back to artwork")
                    .position(
                        x: frame.midX + Self.portraitHorizontalPadding,
                        y: frame.midY
                    )
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : .smooth(duration: 0.48),
                        value: isPortraitArtworkExpanded
                    )
                    .allowsHitTesting(page != .artwork)
                }
            }
            .clipShape(VerticalOnlyClip())
            .padding(
                .horizontal,
                -Self.portraitHorizontalPadding
            )
        }
        .coordinateSpace(
            name: NowPlayingPortraitCoordinateSpace.name
        )
    }

    @ViewBuilder
    private func transientArtworkPageContent(
        for song: Song
    ) -> some View {
        if page == .artwork {
            NowPlayingArtworkPage(
                song: song,
                artworkNamespace: pageArtworkNamespace,
                usesArtworkTransition: false,
                showsArtwork: false,
                onArtworkFrameChange: {
                    guard page == .artwork else { return }
                    artworkPageFrame = $0
                }
            )
            .transition(
                pageContentTransition(for: .artwork)
            )
        }
    }

    private func residentQueuePage(
        for song: Song
    ) -> some View {
        NowPlayingQueuePage(
            song: song,
            presentation: .portrait,
            artworkNamespace: pageArtworkNamespace,
            usesArtworkTransition: false,
            showsSongHeader: false,
            onSongHeaderHiddenChange: {
                isQueueSongHeaderHidden = $0
            },
            onSongHeaderOffsetChange: {
                queueSongHeaderOffset = $0
            }
        )
        .clipped()
        .offset(y: residentQueueOffset)
        .scaleEffect(residentQueueScale)
        .opacity(page == .queue ? 1 : 0)
        .animation(
            NowPlayingPageTransition.residentQueueAnimation(
                from: transitionSourcePage,
                to: transitionDestinationPage,
                reducesMotion: accessibilityReduceMotion
            ),
            value: page
        )
        .allowsHitTesting(page == .queue)
        .accessibilityHidden(page != .queue)
    }

    private func portraitLyricsPage(
        for song: Song,
        onInitialFocusPrepared: (() -> Void)? = nil
    ) -> some View {
        NowPlayingLyricsPage(
            song: song,
            lyrics: lyrics,
            errorMessage: lyricError,
            highlightedLyricID: highlightedLyricID,
            isActive: page == .lyrics,
            isInterfaceHidden: hidesLyricsControls,
            artworkNamespace: pageArtworkNamespace,
            usesArtworkTransition:
                !entersPageFromHiddenQueue,
            showsSongHeader: false,
            onInterfaceInteraction:
                handleLyricsInterfaceInteraction,
            onInterfaceVisibilityChange:
                setAppleMusicLyricsControlsVisible,
            onInitialFocusPrepared: onInitialFocusPrepared
        )
        .accessibilityAction(
            named: lyricsInterfaceAccessibilityActionName
        ) {
            handleLyricsInterfaceInteraction()
        }
    }

    private func residentAppleMusicLyricsPage(
        for song: Song
    ) -> some View {
        portraitLyricsPage(
            for: song,
            onInitialFocusPrepared: {
                markLyricsContentPrepared(for: song.id)
            }
        )
        .id(song.id)
        .offset(y: residentLyricsOffset)
        .scaleEffect(residentLyricsScale)
        .opacity(residentLyricsOpacity)
        .animation(
            NowPlayingPageTransition.residentLyricsAnimation(
                from: transitionSourcePage,
                to: transitionDestinationPage,
                interruptsExit: interruptsLyricsExit,
                reducesMotion: accessibilityReduceMotion
            ),
            value: page
        )
        .allowsHitTesting(page == .lyrics)
        .accessibilityHidden(page != .lyrics)
    }

    private var residentLyricsOffset: CGFloat {
        if page == .lyrics {
            return usesStagedLyricsEntrance
                && !lyricsEntranceState.isPresented
                ? NowPlayingPageTransition.lyricsEntranceOffset
                : 0
        }

        return transitionSourcePage == .lyrics
            && transitionDestinationPage == .artwork
            ? NowPlayingPageTransition.lyricsEntranceOffset
            : 0
    }

    private var residentLyricsScale: CGFloat {
        page == .queue
            ? NowPlayingPageTransition.directLyricsQueueContentScale
            : 1
    }

    private var residentLyricsOpacity: Double {
        guard page == .lyrics else { return 0 }
        return usesStagedLyricsEntrance
            && !lyricsEntranceState.isPresented
            ? 0
            : 1
    }

    private var residentQueueOffset: CGFloat {
        guard page == .artwork,
              !entersPageFromHiddenQueue else {
            return 0
        }
        return NowPlayingPageTransition.queueOffset
    }

    private var residentQueueScale: CGFloat {
        page == .lyrics
            ? NowPlayingPageTransition.directLyricsQueueContentScale
            : 1
    }

    private func sharedPortraitSongHeader(
        for song: Song
    ) -> some View {
        NowPlayingSongHeader(
            song: song,
            artworkNamespace: pageArtworkNamespace,
            usesReferenceLayout: true,
            usesArtworkTransition: false,
            showsArtwork: false
        )
    }

    static func estimatedArtworkFrame(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let inner = size.width - portraitHorizontalPadding * 2
        let artworkSize = max(
            170,
            min(inner + 16, size.height - NowPlayingBottomControls.coreHeight - 92)
        )
        return CGRect(
            x: (inner - artworkSize) / 2,
            y: 8,
            width: artworkSize,
            height: artworkSize
        )
    }

    private var portraitArtworkFrame: CGRect {
        if page == .artwork {
            return displayedArtworkPageFrame
        }

        return CGRect(
            x: 0,
            y: sharedPortraitSongHeaderOffset,
            width: NowPlayingSongHeader.referenceHeight,
            height: NowPlayingSongHeader.referenceHeight
        )
    }

    private var displayedArtworkPageFrame: CGRect {
        guard !isPortraitArtworkExpanded else {
            return artworkPageFrame
        }
        let horizontalInset =
            artworkPageFrame.width
            * (1 - NowPlayingArtworkPage.pausedArtworkScale)
            / 2
        let verticalInset =
            artworkPageFrame.height
            * (1 - NowPlayingArtworkPage.pausedArtworkScale)
            / 2
        return artworkPageFrame.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        )
    }

    private var isPortraitArtworkExpanded: Bool {
        player.isPlaying || !settings.shrinksPausedArtwork
    }

    private var sharedPortraitSongHeaderOffset: CGFloat {
        page == .queue ? queueSongHeaderOffset : 0
    }

    private func pageContentTransition(
        for destination: NowPlayingPage
    ) -> AnyTransition {
        if NowPlayingPageTransition.isDirectLyricsQueueTransition(
            from: transitionSourcePage,
            to: transitionDestinationPage
        ) {
            return NowPlayingPageTransition.directAlternateContent(
                reducesMotion: accessibilityReduceMotion
            )
        }

        return NowPlayingPageTransition.content(
            for: destination,
            entersFromHiddenQueue: entersPageFromHiddenQueue,
            reducesMotion: accessibilityReduceMotion
        )
    }

    private func restoreArtworkTransitionAfterHiddenQueueEntry() async {
        guard entersPageFromHiddenQueue else { return }

        do {
            try await Task.sleep(for: .milliseconds(420))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            entersPageFromHiddenQueue = false
        }
    }

    private func restoreDefaultPageTransition() async {
        guard NowPlayingPageTransition
            .isDirectLyricsQueueTransition(
                from: transitionSourcePage,
                to: transitionDestinationPage
            ) else {
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(460))
        } catch {
            return
        }
        guard !Task.isCancelled,
              page == transitionDestinationPage else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionSourcePage = page
            transitionDestinationPage = page
        }
    }

    private var usesStagedLyricsEntrance: Bool {
        transitionSourcePage == .artwork
            && transitionDestinationPage == .lyrics
            && settings.lyricsStyle == .appleMusic
    }

    private func beginLyricsEntrance() {
        let deadline: ContinuousClock.Instant
        if case let .pending(_, pendingDeadline) =
            lyricsEntranceState {
            deadline = pendingDeadline
        } else {
            deadline = ContinuousClock.now.advanced(
                by: NowPlayingPageTransition.lyricsEntranceDelay
            )
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            lyricsEntranceState = .pending(UUID(), deadline)
        }
    }

    private func interruptLyricsExit() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            lyricsEntranceState = .presented
        }
    }

    private func presentLyricsEntrance() async {
        guard case let .pending(requestID, deadline) =
            lyricsEntranceState else {
            return
        }

        await Task.yield()
        guard !Task.isCancelled,
              lyricsEntranceState == .pending(
                requestID,
                deadline
              ) else {
            return
        }

        if accessibilityReduceMotion {
            finishLyricsEntrance(
                requestID: requestID,
                deadline: deadline,
                animated: false
            )
            return
        }

        let remainingDelay =
            ContinuousClock.now.duration(to: deadline)
        if remainingDelay > .zero {
            do {
                try await Task.sleep(for: remainingDelay)
            } catch {
                return
            }
        }

        guard !Task.isCancelled,
              lyricsEntranceState == .pending(
                requestID,
                deadline
              ) else {
            return
        }

        guard page == .lyrics, usesStagedLyricsEntrance else {
            finishLyricsEntrance(
                requestID: requestID,
                deadline: deadline,
                animated: false
            )
            return
        }

        let giveUp = ContinuousClock.now.advanced(by: .milliseconds(1500))
        while !isLyricsContentPrepared, ContinuousClock.now < giveUp {
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  lyricsEntranceState == .pending(
                    requestID,
                    deadline
                  ) else {
                return
            }
            guard page == .lyrics, usesStagedLyricsEntrance else {
                finishLyricsEntrance(
                    requestID: requestID,
                    deadline: deadline,
                    animated: false
                )
                return
            }
        }

        finishLyricsEntrance(
            requestID: requestID,
            deadline: deadline,
            animated: true
        )
    }

    private func finishLyricsEntrance(
        requestID: UUID,
        deadline: ContinuousClock.Instant,
        animated: Bool
    ) {
        guard lyricsEntranceState == .pending(
            requestID,
            deadline
        ) else {
            return
        }

        if animated {
            withAnimation(
                NowPlayingPageTransition.lyricsEntranceAnimation
            ) {
                lyricsEntranceState = .presented
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                lyricsEntranceState = .presented
            }
        }
    }

    private var isLyricsContentPrepared: Bool {
        lyrics.isEmpty
            || preparedLyricsSongID == player.currentSong?.id
    }

    private func markLyricsContentPrepared(for songID: Song.ID) {
        guard player.currentSong?.id == songID else { return }
        preparedLyricsSongID = songID
    }

    private var lyricsInterfaceAccessibilityActionName: String {
        if settings.lyricsStyle == .appleMusic {
            return "Show player controls"
        }
        return showsLyricsControls
            ? "Hide player controls"
            : "Show player controls"
    }

    private func handleLyricsInterfaceInteraction() {
        if settings.lyricsStyle == .appleMusic {
            registerAppleMusicControlsActivity()
        } else {
            toggleLyricsControls()
        }
    }

    private func registerAppleMusicControlsActivity() {
        guard usesAutoHidingAppleMusicInterface else { return }

        appleMusicControlsActivityGeneration &+= 1
        guard !showsLyricsControls else { return }

        withAnimation(
            NowPlayingInterfaceTransition.interfaceAnimation(
                isVisible: true,
                reducesMotion: accessibilityReduceMotion
            )
        ) {
            showsLyricsControls = true
        }
    }

    private func setAppleMusicLyricsControlsVisible(_ isVisible: Bool) {
        guard usesAutoHidingAppleMusicInterface else { return }
        if isVisible {
            registerAppleMusicControlsActivity()
            return
        }

        guard showsLyricsControls,
              !accessibilityVoiceOverEnabled else {
            return
        }
        cancelAppleMusicControlsAutoHide()
        withAnimation(
            NowPlayingInterfaceTransition.interfaceAnimation(
                isVisible: false,
                reducesMotion: accessibilityReduceMotion
            )
        ) {
            showsLyricsControls = false
        }
    }

    private func toggleLyricsControls() {
        withAnimation(
            accessibilityReduceMotion
                ? nil
                : .smooth(duration: 0.3)
        ) {
            showsLyricsControls.toggle()
        }
    }

    private func cancelAppleMusicControlsAutoHide() {
        appleMusicControlsActivityGeneration &+= 1
    }

}

private struct NowPlayingBeatAnalysisTaskID: Equatable {
    let songID: String?
    let isPlaybackReady: Bool
    let isEnabled: Bool
}

private enum NowPlayingLyricsEntranceState: Hashable {
    case presented
    case pending(UUID, ContinuousClock.Instant)

    var isPresented: Bool {
        switch self {
        case .presented:
            true
        case .pending:
            false
        }
    }
}

private struct VerticalOnlyClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -1_000, dy: 0))
    }
}
