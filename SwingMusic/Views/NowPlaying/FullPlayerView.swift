import SwiftUI
import AVKit
import MediaPlayer

struct FullPlayerView: View {
    @Namespace private var coverNS
    @EnvironmentObject var state: AppState
    @ObservedObject var player = AudioPlayer.shared
    @Binding var show: Bool
    @State private var bgImage: UIImage?
    @State private var prevBgImage: UIImage?
    @State private var bgTransition: CGFloat = 1
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var drag: CGFloat = 0
    @State private var hDrag: CGFloat = 0
    @State private var isFavorite = false
    @State private var showPlaylistSheet = false
    @State private var controlsVisible = true
    @State private var immersiveTimer: Task<Void, Never>?
    @State private var showSleepTimer = false
    @State private var showEqualizer = false
    @State private var showOptionsSheet = false
    @State private var controlsHeight: CGFloat = 250
    @ObservedObject var sleepTimer = SleepTimer.shared
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    @AppStorage("albumArtTapAction") private var albumArtTapAction = "album"

    var body: some View {
        GeometryReader { geo in
            let width = min(max(geo.size.width - 56, 280), 336)

            let cornerR: CGFloat = 16.5

            ZStack {
                bg
                VStack(spacing: 0) {
                    handle
                    playerContent(width: width)
                }
            }
            .sheet(isPresented: $showPlaylistSheet) {
                AddToPlaylistSheet(track: player.current)
                    .environmentObject(state)
            }
            .frame(width: geo.size.width, height: geo.size.height - geo.safeAreaInsets.top)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: cornerR, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: cornerR, style: .continuous))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .offset(y: drag)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: drag)
            .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.88, blendDuration: 0.15), value: showLyrics)

            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        guard !showLyrics else { return }
                        let h = value.translation.width
                        let v = value.translation.height
                        if v > 0 && abs(v) > abs(h) { drag = v }
                    }
                    .onEnded { value in
                        let h = value.translation.width
                        let v = value.translation.height

                        if showLyrics {
                            if abs(h) > 60 && abs(h) > abs(v) * 1.5 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation { showLyrics = false }
                            }
                            drag = 0
                            return
                        }

                        if v > 120 && abs(v) > abs(h) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            show = false
                        }
                        withAnimation(.spring(response: 0.3)) { drag = 0 }
                    }
            )
        }
        .ignoresSafeArea()

        .environment(\.colorScheme, .dark)
        .task { await loadBG(); await checkFavorite() }
        .onChange(of: player.current) { _, _ in Task { await loadBG(); await checkFavorite() } }
        .onChange(of: showLyrics) { _, newVal in

            UIApplication.shared.isIdleTimerDisabled = newVal
            if newVal {
                showControlsBriefly()
            } else {
                immersiveTimer?.cancel()
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var bg: some View {

        let coverOpacity = isDark ? 0.8 : 0.8
        return ZStack {
            (isDark ? Color.black : Color(.systemBackground))

            if let prev = prevBgImage {
                Image(uiImage: prev)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 60, opaque: true)
                    .saturation(isDark ? 1.0 : 1.4)
                    .opacity(coverOpacity * (1 - bgTransition))
            }

            if let img = bgImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 60, opaque: true)
                    .saturation(isDark ? 1.0 : 1.4)
                    .opacity(coverOpacity * bgTransition)
            }

            LinearGradient(
                colors: isDark
                    ? [.black.opacity(0.2), .black.opacity(0.5), .black.opacity(0.7)]
                    : [Color(.systemBackground).opacity(0.3),
                       Color(.systemBackground).opacity(0.46),
                       Color(.systemBackground).opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var handle: some View {
        VStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(.primary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 22)
            HStack { Spacer(); Spacer() }.frame(height: 22)
        }
    }

    private func playerContent(width: CGFloat) -> some View {
        let bigSize = min(width, 320)
        let playScale: CGFloat = player.playing ? 1.0 : 0.85

        return ZStack {

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Spacer().frame(height: 72)
                    LyricsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: width)
                Spacer(minLength: 0)
            }
            .mask {
                if showLyrics && controlsVisible {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 60)
                        Color.clear
                            .frame(height: controlsHeight)
                    }
                } else {
                    Color.black
                }
            }
            .opacity(showLyrics ? 1 : 0)
            .allowsHitTesting(showLyrics)
            .simultaneousGesture(TapGesture().onEnded { if showLyrics { showControlsBriefly() } })

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: bigSize + 50)
                            trackInfo(width: width)
                            Spacer()
                        }
                        .opacity(showLyrics ? 0 : 1)
                        .allowsHitTesting(!showLyrics)

                        VStack(spacing: 0) {
                            if let t = player.current {
                                if showLyrics {
                                    HStack(alignment: .top, spacing: 12) {
                                        AlbumArt(track: t, size: 54)
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .matchedGeometryEffect(id: "cover", in: coverNS)
                                            .shadow(color: .black.opacity(0.13), radius: 4, y: 1)
                                            .contentShape(Rectangle())
                                            .onTapGesture { toggleLyrics() }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(t.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                                            Text(t.artist).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.5)).lineLimit(1)
                                        }
                                        .padding(.top, 2)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.top, 8).padding(.leading, 10)
                                    .animation(.easeInOut(duration: 0.5), value: controlsVisible)
                                } else {
                                    coverCarousel(bigSize: bigSize, playScale: playScale)
                                }
                            }
                        }
                        .allowsHitTesting(true)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0.2), value: showLyrics)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.playing)

                    VStack(spacing: 0) {
                        timeline(width: width)
                        Spacer(minLength: 40)
                        controls(width: width)
                        Spacer(minLength: 40)
                        volumeBar(width: width)
                        Spacer(minLength: 30)
                        bottomToolbar(width: width)
                        Spacer(minLength: 20)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { controlsHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, new in controlsHeight = new }
                        }
                    )
                    .opacity(!showLyrics || controlsVisible ? 1 : 0)
                    .offset(y: (!showLyrics || controlsVisible) ? 0 : 300)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!showLyrics || controlsVisible)
                }
                .frame(width: width)
                .animation(.easeInOut(duration: 0.5), value: controlsVisible)
                Spacer(minLength: 0)
            }
        }
    }

    private func slot(for bigSize: CGFloat) -> CGFloat { bigSize + 70 }

    private func adjacentTrack(_ d: Int) -> Track? {
        let i = player.index + d
        return player.queue.indices.contains(i) ? player.queue[i] : nil
    }

    private func coverCarousel(bigSize: CGFloat, playScale: CGFloat) -> some View {
        let s = slot(for: bigSize)
        return ZStack {
            if let pt = adjacentTrack(-1) {
                cover(pt, bigSize: bigSize)
                    .offset(x: -s + hDrag)
                    .opacity(coverOpacity(atX: -s + hDrag, slot: s))
            }
            if let nt = adjacentTrack(1) {
                cover(nt, bigSize: bigSize)
                    .offset(x: s + hDrag)
                    .opacity(coverOpacity(atX: s + hDrag, slot: s))
            }
            if let t = player.current {
                cover(t, bigSize: bigSize)
                    .scaleEffect(playScale)
                    .matchedGeometryEffect(id: "cover", in: coverNS)
                    .offset(x: hDrag)
                    .opacity(coverOpacity(atX: hDrag, slot: s))
                    .onTapGesture { albumArtTapped(t) }
            }
        }
        .frame(width: bigSize, height: bigSize)
        .contentShape(Rectangle())
        .gesture(artSwipeGesture(slot: s))
        .padding(.top, 20)
    }

    private func cover(_ track: Track, bigSize: CGFloat) -> some View {
        AlbumArt(track: track, size: bigSize)
            .frame(width: bigSize, height: bigSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
    }

    private func coverOpacity(atX x: CGFloat, slot: CGFloat) -> Double {
        let d = min(abs(x) / slot, 1)
        return Double(1 - d * 0.55)
    }

    private func artSwipeGesture(slot: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !showLyrics else { return }
                let h = value.translation.width
                guard abs(h) > abs(value.translation.height) else { return }

                let hasNeighbor = adjacentTrack(h < 0 ? 1 : -1) != nil
                hDrag = hasNeighbor ? h : h * 0.25
            }
            .onEnded { value in
                guard !showLyrics else { return }
                let h = value.translation.width
                let v = value.translation.height
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let dir: CGFloat = h < 0 ? -1 : 1
                let target = player.index + (h < 0 ? 1 : -1)
                let commit = (abs(h) > slot * 0.32 || abs(velocity) > 200)
                    && abs(h) > abs(v)
                    && player.queue.indices.contains(target)
                guard commit else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { hDrag = 0 }
                    return
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()

                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    hDrag = dir * slot
                } completion: {
                    player.jump(to: target)
                    var instant = Transaction(); instant.disablesAnimations = true
                    withTransaction(instant) { hDrag = 0 }
                }
            }
    }

    private func artistTapped(_ t: Track) {
        let hash = t.artisthash
        guard !hash.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let artist = Artist(stub: hash, name: t.artist, image: t.image)
        state.navigationTarget = .artist(artist)
    }

    private func albumArtTapped(_ t: Track) {
        if albumArtTapAction == "lyrics" {
            toggleLyrics()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let album = Album(stub: t.albumhash, title: t.album, image: t.image, date: t.date, albumartists: t.albumartists)
            state.navigationTarget = .album(album)
        }
    }

    private func toggleLyrics() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { showLyrics.toggle() }
        if showLyrics { showControlsBriefly() } else {
            immersiveTimer?.cancel()
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
        }
    }

    private func showControlsBriefly() {
        immersiveTimer?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
        immersiveTimer = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, showLyrics, player.playing else { return }
            withAnimation(.easeInOut(duration: 0.6)) { controlsVisible = false }
        }
    }

    private func trackInfo(width: CGFloat) -> some View {
        HStack {
            if let t = player.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(.system(size: 24, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    Button {
                        artistTapped(t)
                    } label: {
                        Text(t.artist).font(.system(size: 18)).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let newState = !isFavorite
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isFavorite = newState }
                        Task { try? await API.shared.toggleFavorite(hash: t.trackhash, type: "track", add: newState) }
                    } label: {
                        ZStack {
                            Circle().fill(isFavorite ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.1)).frame(width: 50, height: 50)
                            Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 18, weight: .semibold)).foregroundStyle(isFavorite ? Color.yellow : Color.primary)
                        }
                        .contentShape(Circle())
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showOptionsSheet = true
                    } label: {
                        ZStack {
                            Circle().fill(.primary.opacity(0.1)).frame(width: 50, height: 50)
                            Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func timeline(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            ThinSlider(value: Binding(get: { min(max(0, player.time), max(player.total, 1)) }, set: { player.seek($0) }), range: 0...max(player.total, 1), trackHeight: 4, activeColor: .primary.opacity(0.9), inactiveColor: .primary.opacity(0.12))
            HStack {
                Text(player.time.mmss)
                Spacer()
                Text(player.audioQuality.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.25))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.08), in: Capsule())
                Spacer()
                Text("-" + max(0, player.total - player.time).mmss)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.primary.opacity(0.35))
        }.frame(maxWidth: .infinity)
    }

    private func controls(width: CGFloat) -> some View {
        HStack(spacing: 0) {

            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(player.shuffle ? Color.blue : .primary.opacity(0.45))
            }.buttonStyle(Pressed()).frame(maxWidth: .infinity)

            Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); player.prev() } label: { Image(systemName: "backward.fill").font(.system(size: 30)).foregroundStyle(.primary) }.buttonStyle(Pressed()).frame(maxWidth: .infinity)
            Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { player.toggle() } } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)).font(.system(size: 46)).foregroundStyle(.primary).frame(width: 56) }.buttonStyle(Pressed()).frame(maxWidth: .infinity)
            Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)).foregroundStyle(.primary) }.buttonStyle(Pressed()).frame(maxWidth: .infinity)

            Button { player.cycleLoop() } label: {
                Image(systemName: player.loop == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(player.loop != .off ? Color.blue : .primary.opacity(0.45))
            }.buttonStyle(Pressed()).frame(maxWidth: .infinity)
        }.frame(width: min(width, 340), alignment: .center)
    }

    private func bottomToolbar(width: CGFloat) -> some View {
        ZStack {
            AirPlayButton().frame(width: 28, height: 28).tint(.primary.opacity(0.7))
            HStack {
                Button { toggleLyrics() } label: { Image(systemName: "quote.bubble").font(.system(size: 18)).foregroundStyle(showLyrics ? Color.primary : Color.primary.opacity(0.5)) }
                if sleepTimer.active {
                    Button { showSleepTimer = true } label: { HStack(spacing: 4) { Image(systemName: "moon.fill").font(.system(size: 11)); Text(sleepTimer.displayTime).font(.system(size: 11, weight: .medium, design: .monospaced)) }.foregroundStyle(.blue).padding(.horizontal, 8).padding(.vertical, 4).background(.blue.opacity(0.15), in: Capsule()) }
                }
                Spacer()
                Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); showQueue = true } label: { Image(systemName: "list.bullet").font(.system(size: 18)).foregroundStyle(.primary.opacity(0.5)) }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showQueue) {
            QueueView(backgroundImage: bgImage)
                .presentationBackground { SheetBlurBackground(image: bgImage) }
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
                .presentationDetents([.medium])
                .presentationBackground { SheetBlurBackground(image: bgImage) }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheet()
                .presentationDetents([.large])
                .presentationBackground { SheetBlurBackground(image: bgImage) }
        }
        .sheet(isPresented: $showOptionsSheet) {
            PlayerOptionsSheet(showSleepTimer: $showSleepTimer, showEqualizer: $showEqualizer, showPlaylistSheet: $showPlaylistSheet)
                .environmentObject(state)
                .presentationDetents([.medium])
                .presentationBackground { SheetBlurBackground(image: bgImage) }
        }
    }

    private func volumeBar(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(.primary.opacity(0.4))
            SystemVolumeSlider()
                .frame(height: 24)
                .tint(.primary.opacity(0.7))
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.primary.opacity(0.4))
        }.frame(maxWidth: .infinity).padding(.top, 10)
    }

    private func loadBG() async {
        guard let t = player.current, let url = API.shared.img(t.image) else { return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: req), let img = UIImage(data: data) else { return }

        prevBgImage = bgImage
        bgTransition = 0
        bgImage = img
        withAnimation(.easeInOut(duration: 1.2)) {
            bgTransition = 1
        }

        try? await Task.sleep(for: .seconds(1.5))
        prevBgImage = nil
    }

    private func checkFavorite() async {
        guard let t = player.current else { isFavorite = false; return }
        isFavorite = (try? await API.shared.checkFavorite(hash: t.trackhash, type: "track")) ?? false
    }
}

struct SheetBlurBackground: View {
    var image: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            (isDark ? Color.black : Color(.systemBackground))
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60, opaque: true)
                    .saturation(isDark ? 1.0 : 1.4)
                    .opacity(isDark ? 0.6 : 0.7)
            }
            (isDark ? Color.black.opacity(0.4) : Color(.systemBackground).opacity(0.42))
        }
        .ignoresSafeArea()
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.tintColor = .label; v.activeTintColor = .systemBlue; v.prioritizesVideoDevices = false; return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.showsRouteButton = false
        v.showsVolumeSlider = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let slider = v.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.minimumTrackTintColor = UIColor.label.withAlphaComponent(0.7)
                slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.1)

                let empty = UIImage()
                slider.setThumbImage(empty, for: .normal)
                slider.setThumbImage(empty, for: .highlighted)
            }
        }
        return v
    }
    func updateUIView(_ v: MPVolumeView, context: Context) {}
}
