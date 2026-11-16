import SwiftUI

struct NowPlayingQueuePage: View {
    @Environment(PlayerStore.self) private var player

    let song: Song
    let presentation: NowPlayingLyricsPresentation
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsSongHeader: Bool
    let onSongHeaderHiddenChange: (Bool) -> Void
    let onSongHeaderOffsetChange: (CGFloat) -> Void

    @State private var songHeaderHeight: CGFloat = 0
    @State private var isSongHeaderHidden = false
    @State private var isSongHeaderAtRest = true

    init(
        song: Song,
        presentation: NowPlayingLyricsPresentation,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsSongHeader: Bool = true,
        onSongHeaderHiddenChange:
            @escaping (Bool) -> Void = { _ in },
        onSongHeaderOffsetChange:
            @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.song = song
        self.presentation = presentation
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsSongHeader = showsSongHeader
        self.onSongHeaderHiddenChange = onSongHeaderHiddenChange
        self.onSongHeaderOffsetChange = onSongHeaderOffsetChange
    }

    var body: some View {
            ScrollViewReader { scrollProxy in
            List {
                Section {
                    ForEach(previousEntries) { entry in
                        queueRow(entry, dimmed: true)
                    }
                    if !previousEntries.isEmpty {
                        Color.clear
                            .frame(height: 20)
                            .offset(y: middleShift)
                            .listRowInsets(.init())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                Color.clear
                    .frame(height: 1)
                    .background(ScrollViewFinder { scroll.scrollView = $0 })
                    .offset(y: middleShift)
                    .id(Self.currentAnchorID)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if presentation == .portrait {
                    Group {
                        if showsSongHeader {
                            NowPlayingSongHeader(
                                song: song,
                                artworkNamespace: artworkNamespace,
                                usesReferenceLayout: true,
                                usesArtworkTransition:
                                    usesArtworkTransition
                                    && isSongHeaderAtRest
                            )
                        } else {
                            Color.clear
                                .frame(
                                    height:
                                        NowPlayingSongHeader
                                        .referenceHeight
                                )
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { newHeight in
                        if newHeight > 0 {
                            songHeaderHeight = newHeight
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                        scroll.headerY = $0
                        refreshSongHeader()
                    }
                    .offset(y: middleShift)
                    .onAppear {
                        scroll.headerVisible = true
                        refreshSongHeader()
                    }
                    .onDisappear {
                        scroll.headerVisible = false
                        refreshSongHeader()
                    }
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text("Up Next")
                        .font(.title2.bold())
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
                        .offset(y: middleShift)
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if upcomingEntries.isEmpty {
                        ContentUnavailableView(
                            "Nothing up next",
                            systemImage: "list.bullet"
                        )
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(
                            .init(
                                top: 24,
                                leading: 0,
                                bottom: 24,
                                trailing: 0
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(upcomingEntries) { entry in
                            queueRow(entry, dimmed: false)
                        }
                    }
                } header: {
                    NowPlayingQueueModeControls()
                        .padding(.vertical, 8)
                        .frame(height: 60)
                        .opacity(isSongHeaderHidden ? 0 : 1)
                        .allowsHitTesting(!isSongHeaderHidden)
                        .accessibilityHidden(isSongHeaderHidden)
                        .offset(y: middleShift)
                        .textCase(nil)
                        .listRowInsets(.init())
                }

                // room below a short Up Next, so the current track can still scroll to the top
                Color.clear
                    .frame(height: bottomFiller)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.visible)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 1)
            .environment(\.defaultMinListHeaderHeight, 0)
            .overlay(alignment: .top) { draggedRow }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                scroll.listY = $0
                refreshSongHeader()
            }
            .padding(.bottom, bottomContentInset)
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { geometry in
                    max(
                        geometry.contentOffset.y
                            + geometry.contentInsets.top,
                        0
                    )
                }
            ) { _, offset in
                scroll.offset = offset
                let now = CACurrentMediaTime()
                scroll.samples = scroll.samples.filter { now - $0.time < 0.1 } + [(now, offset)]
                refreshSongHeader()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            } action: { _, height in
                visibleHeight = height
            }
            .onScrollPhaseChange { old, phase in
                if phase == .interacting { scroll.followsCurrent = false }
                if phase == .idle { scroll.followsCurrent = isSongHeaderAtRest }
                if old == .interacting { snap(scrollProxy) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.shownNotification)) { _ in
                scrollToCurrent(scrollProxy)
            }
            .onChange(of: bottomFiller) {
                if scroll.followsCurrent { scrollToCurrent(scrollProxy) }
            }
            .onChange(of: player.currentIndex) {
                if scroll.followsCurrent {
                    scrollToCurrent(scrollProxy)
                } else {
                    refreshSongHeader()
                }
            }
            }
            // An overlay and mask, not a resize: changing the list's layout here moved its rows and flipped the header back.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: isSongHeaderHidden ? 60 : 0)
                    Color.black
                }
            }
            .overlay(alignment: .top) {
                NowPlayingQueueModeControls()
                    .padding(.vertical, 8)
                    .frame(height: 60)
                    .opacity(isSongHeaderHidden ? 1 : 0)
                    .allowsHitTesting(isSongHeaderHidden)
                    .accessibilityHidden(!isSongHeaderHidden)
            }
    }

    private static let currentAnchorID = "queue-current"
    @State private var scroll = ScrollState()
    @ScaledMetric(relativeTo: .body) private var rowHeight = NowPlayingQueueRow.baseHeight
    @State private var visibleHeight: CGFloat = 0

    // From row counts, not the list's content size, which would change with it and loop.
    private var bottomFiller: CGFloat {
        let upNext = songHeaderHeight + 60 + CGFloat(upcomingEntries.count) * rowHeight
        return max(1, visibleHeight - upNext)
    }

    private final class ScrollState {
        var offset: CGFloat = 0
        var followsCurrent = true
        var samples: [(time: CFTimeInterval, offset: CGFloat)] = []

        // over the last tenth of a second, so a finger held still before lifting isn't a flick
        var velocity: CGFloat {
            let now = CACurrentMediaTime()
            guard let first = samples.first(where: { now - $0.time < 0.1 }), let last = samples.last,
                  last.time > first.time else { return 0 }
            return (last.offset - first.offset) / CGFloat(last.time - first.time)
        }
        var headerVisible = false
        var headerY: CGFloat = 0
        var listY: CGFloat = 0
        weak var scrollView: UIScrollView?
    }

    // The shared song header follows its slot in the list, measured while on screen.
    private func refreshSongHeader() {
        if scroll.headerVisible {
            updateSongHeaderState(for: scroll.listY - scroll.headerY + 1)
            return
        }
        // off screen: hidden if it left past the top, out of the way below otherwise
        updateSongHeaderState(for: scroll.headerY < scroll.listY ? songHeaderHeight : -visibleHeight)
    }

    // Like Apple Music: a scroll released between the current track and a screen of the tracks before it settles at one end.
    private func snap(_ proxy: ScrollViewProxy) {
        // measured, since row height estimates drift over a long queue
        guard scroll.headerVisible else { return }
        let below = scroll.headerY - scroll.listY - 1
        let top = min(visibleHeight, below + scroll.offset)
        guard below > 1, below < top - 1 else { return }
        let velocity = scroll.velocity
        let towardTop = abs(velocity) > 300 ? velocity < 0 : top - below < below
        if towardTop {
            withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(Self.currentAnchorID, anchor: .bottom) }
        } else {
            scroll.followsCurrent = true
            withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(Self.currentAnchorID, anchor: .top) }
        }
    }
    static let shownNotification = Notification.Name("NowPlayingQueuePageShown")

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        scroll.followsCurrent = true
        var t = Transaction()
        t.disablesAnimations = true
        DispatchQueue.main.async {
            withTransaction(t) { proxy.scrollTo(Self.currentAnchorID, anchor: .top) }
        }
    }

    private var previousEntries: [UpcomingQueueEntry] {
        guard player.currentIndex > 0 else { return [] }
        var occurrences: [String: Int] = [:]
        return (0 ..< min(player.currentIndex, player.queue.count)).map { index in
            let song = player.queue[index]
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            return UpcomingQueueEntry(
                id: UpcomingQueueEntry.ID(songID: "previous-" + song.id, occurrence: occurrence),
                queueIndex: index,
                song: song
            )
        }
    }

    private var upcomingEntries: [UpcomingQueueEntry] {
        var occurrences: [String: Int] = [:]
        return player.unplayedQueueIndices.compactMap { index in
            guard player.queue.indices.contains(index) else {
                return nil
            }
            let song = player.queue[index]
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            return UpcomingQueueEntry(
                id: UpcomingQueueEntry.ID(
                    songID: song.id,
                    occurrence: occurrence
                ),
                queueIndex: index,
                song: song
            )
        }
    }

    private var bottomContentInset: CGFloat {
        presentation == .portrait
            ? NowPlayingBottomControls.coreHeight
            : 12
    }

    private func updateSongHeaderState(for offset: CGFloat) {
        guard presentation == .portrait else { return }

        onSongHeaderOffsetChange(
            -min(offset, max(songHeaderHeight, 0))
        )

        let isHidden =
            songHeaderHeight > 0
            && offset >= songHeaderHeight
        if isSongHeaderHidden != isHidden {
            isSongHeaderHidden = isHidden
            onSongHeaderHiddenChange(isHidden)
        }

        let isAtRest = abs(offset) <= 1
        if isSongHeaderAtRest != isAtRest {
            isSongHeaderAtRest = isAtRest
        }
    }


    // MARK: Reordering from the drag handle

    private struct QueueDrag {
        let from: Int
        let startTop: CGFloat
        let startOffset: CGFloat
        var translation: CGFloat = 0
        // where the track would land: how many other queue entries end up above it
        var landing: Int
        var dropTop: CGFloat?
    }

    @State private var drag: QueueDrag?
    @State private var titleHeight: CGFloat = 48

    private func queueRow(_ entry: UpcomingQueueEntry, dimmed: Bool) -> some View {
        let i = entry.queueIndex
        return NowPlayingQueueRow(
            entry: entry,
            dimmed: dimmed,
            onDrag: { top, dy in dragChanged(i, top: top, dy: dy) },
            onDrop: dropDragged,
            onMove: { to in player.moveQueueItem(from: i, to: to) },
            onRemove: { withAnimation(.smooth(duration: 0.28)) { player.removeQueueItem(at: i) } }
        )
        .opacity(drag?.from == i ? 0 : 1)
        .offset(y: shift(for: i))
    }

    @ViewBuilder
    private var draggedRow: some View {
        if let d = drag, player.queue.indices.contains(d.from) {
            NowPlayingQueueRow(
                entry: UpcomingQueueEntry(id: .init(songID: "dragged", occurrence: 0), queueIndex: d.from, song: player.queue[d.from]),
                dimmed: false
            )
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .padding(.horizontal, -8)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
            .offset(y: d.dropTop ?? d.startTop + d.translation)
            .allowsHitTesting(false)
        }
    }

    // The current track's block: gap, header, mode controls and the Up Next title.
    private var middleHeight: CGFloat {
        (player.currentIndex > 0 ? 20 : 0) + 1 + (presentation == .portrait ? songHeaderHeight : 0) + 60 + titleHeight
    }

    // Content position from row counts; queue rows have a fixed height.
    private func virtualTop(_ j: Int) -> CGFloat {
        let c = player.currentIndex
        if j <= c { return CGFloat(j) * rowHeight }
        return CGFloat(c) * rowHeight + middleHeight + CGFloat(j - c - 1) * rowHeight
    }

    private func height(_ j: Int) -> CGFloat { j == player.currentIndex ? middleHeight : rowHeight }

    private var middleShift: CGFloat { shift(for: player.currentIndex) }

    // Entries between the dragged track and where it would land step aside by one row.
    private func shift(for k: Int) -> CGFloat {
        guard let d = drag, k != d.from else { return 0 }
        if d.landing > d.from, k > d.from, k <= d.landing { return -rowHeight }
        if d.landing < d.from, k >= d.landing, k < d.from { return rowHeight }
        return 0
    }

    private func landing(for d: QueueDrag) -> Int {
        let center = virtualTop(d.from) + d.translation + scroll.offset - d.startOffset + rowHeight / 2
        return player.queue.indices.reduce(0) { n, k in
            k != d.from && virtualTop(k) + height(k) / 2 < center ? n + 1 : n
        }
    }

    private func dragChanged(_ from: Int, top: CGFloat, dy: CGFloat) {
        if drag == nil {
            guard player.queue.indices.contains(from), from != player.currentIndex else { return }
            drag = QueueDrag(from: from, startTop: top - scroll.listY, startOffset: scroll.offset, landing: from)
            scroll.followsCurrent = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            autoScroll()
        }
        guard drag?.dropTop == nil else { return }
        drag?.translation = dy
        updateLanding()
    }

    private func updateLanding() {
        guard let d = drag else { return }
        let f = landing(for: d)
        guard f != d.landing else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.smooth(duration: 0.2)) {
            drag?.landing = f
            refreshSongHeader()
        }
    }

    private func dropDragged() {
        guard var d = drag, d.dropTop == nil else { return }
        let f = d.landing
        let finalTop = f > d.from ? virtualTop(f) + height(f) - rowHeight : f < d.from ? virtualTop(f) : virtualTop(d.from)
        d.dropTop = d.startTop + finalTop - virtualTop(d.from) - (scroll.offset - d.startOffset)
        withAnimation(.smooth(duration: 0.2)) { drag = d }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // animated: when the change is above the visible rows, the list keeps them in place and they slide back
            withAnimation(.smooth(duration: 0.25)) {
                player.moveQueueItem(from: d.from, to: f > d.from ? f + 1 : f)
                drag = nil
                refreshSongHeader()
            }
        }
    }

    // Scrolls while the dragged track is held near the top or bottom edge.
    private func autoScroll() {
        Task { @MainActor in
            while let d = drag, d.dropTop == nil {
                if let sv = scroll.scrollView {
                    let center: CGFloat = d.startTop + d.translation + rowHeight / 2
                    let upper: CGFloat = (isSongHeaderHidden ? 60 : 0) + 50
                    let lower: CGFloat = visibleHeight - 50
                    var step: CGFloat = 0
                    if center < upper { step = -min(14, (upper - center) / 4 + 2) }
                    if center > lower { step = min(14, (center - lower) / 4 + 2) }
                    let minY: CGFloat = -sv.adjustedContentInset.top
                    let maxY: CGFloat = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                    let y: CGFloat = min(max(sv.contentOffset.y + step, minY), maxY)
                    if y != sv.contentOffset.y {
                        sv.contentOffset.y = y
                        updateLanding()
                    }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

// The List's scroll view, for scrolling while a track is dragged.
private struct ScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var v = view.superview
            while let x = v, !(x is UIScrollView) { v = x.superview }
            if let sv = v as? UIScrollView { found(sv) }
        }
    }
}

private struct NowPlayingQueueModeControls: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            modeButton(
                systemImage: "shuffle",
                isSelected: player.isShuffled,
                accessibilityLabel:
                    player.isShuffled
                        ? "Turn off shuffle"
                        : "Turn on shuffle",
                action: toggleShuffle
            )

            modeButton(
                systemImage: player.repeatMode.systemImage,
                isSelected: player.repeatMode != .off,
                accessibilityLabel:
                    player.repeatMode.accessibilityTitle,
                action: cycleRepeatMode
            )
        }
        .disabled(player.isListenTogetherSessionActive)
        .accessibilityHint(
            player.isListenTogetherSessionActive
                ? ""
                : ""
        )
    }

    private func modeButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(
                    .symbolEffect(.replace.downUp.wholeSymbol)
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(
                    isSelected
                        ? .black.opacity(0.62)
                        : .white.opacity(0.86)
                )
                .background(
                    .white.opacity(isSelected ? 0.7 : 0.12),
                    in: .rect(cornerRadius: 22)
                )
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleShuffle() {
        withAnimation(.smooth(duration: 0.34)) {
            player.toggleShuffle()
        }
    }

    private func cycleRepeatMode() {
        withAnimation(.smooth(duration: 0.34)) {
            player.cycleRepeatMode()
        }
    }
}

private struct NowPlayingQueueRow: View {
    @Environment(PlayerStore.self) private var player

    let entry: UpcomingQueueEntry
    var dimmed = false
    // top on screen, and how far the handle has been dragged
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDrop: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onRemove: (() -> Void)?
    @State private var top: CGFloat = 0
    static let baseHeight: CGFloat = 56
    // fixed, so the page knows exactly how tall the tracks above the current one are
    @ScaledMetric(relativeTo: .body) private var height = baseHeight
    // matches TrackRow
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
        Button(action: play) {
            HStack(spacing: 12) {
                ArtworkImage(
                    url: entry.song.artworkURL,
                    cornerRadius: 6
                )
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.song.name)
                        .font(.system(size: titleSize))
                        .lineLimit(1)
                        .explicitBadge(entry.song.isExplicit)

                    Text(entry.song.artistText)
                        .font(.system(size: detailSize))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .frame(height: height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.55 : 1)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 44, height: height)
                .contentShape(.rect)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .global).minY
                } action: { top = $0 }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { onDrag?(top, $0.translation.height) }
                        .onEnded { _ in onDrop?() }
                )
                .accessibilityHidden(true)
        }
        .pullActions(leading: removeAction, trailing: removeAction)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let onMove {
                if entry.queueIndex > 0 {
                    Button("Move Up") { onMove(entry.queueIndex - 1) }
                }
                if entry.queueIndex + 1 < player.queue.count {
                    Button("Move Down") { onMove(entry.queueIndex + 2) }
                }
            }
            if let onRemove {
                Button("Remove from Queue", action: onRemove)
            }
        }
        .listRowInsets(.init())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var removeAction: PullAction? {
        onRemove.map { PullAction(label: "Remove", icon: "trash", armedColor: .red, perform: $0) }
    }

    private func play() {
        Task {
            await player.playFromQueue(at: entry.queueIndex)
        }
    }
}

private struct UpcomingQueueEntry: Identifiable {
    struct ID: Hashable {
        let songID: String
        let occurrence: Int
    }

    let id: ID
    let queueIndex: Int
    let song: Song
}


