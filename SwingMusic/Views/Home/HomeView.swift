import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    @State private var heroes: [HeroPick] = []

    private struct HeroPick: Identifiable {
        let album: Album
        let label: String
        var id: String { album.albumhash }
    }

    private enum HomeRoute: Hashable {
        case allAlbums, allArtists
    }

    @State private var didLoad = false

    private var isLoading: Bool { !didLoad && state.homeSections.isEmpty }

    var body: some View {
        NavigationStack(path: $state.homePath) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if isLoading {
                        skeleton
                    } else if state.homeSections.isEmpty {
                        emptyState
                    } else {

                        ForEach(state.homeSections) { serverSection($0) }
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.top, 12)
            }
            .squeezeMiniPlayer(state)
            .background { AmbientBackground() }
            .navigationTitle("Listening Now")
            .refreshable {
                await state.loadHomeSections()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .allAlbums: AlbumsGridView()
                case .allArtists: ArtistsGridView()
                }
            }
            .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(id: $0.id, name: $0.name) }
            .navigationDestination(for: Mix.self) { MixDetailView(mix: $0) }
        }
        .task {
            await state.loadHomeSections()
            didLoad = true
        }
    }

    private func playAlbum(_ album: Album, shuffled: Bool = false) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            guard let tracks = try? await API.shared.albumTracks(album.albumhash),
                  !tracks.isEmpty else { return }
            state.player.playAll(tracks, shuffled: shuffled)
        }
    }

    private func playTrack(_ track: Track, from queue: [Track]) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        state.player.play(track, from: queue)
    }

    private var heroCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(heroes) { pick in
                    heroCard(pick.album, label: pick.label)
                        .containerRelativeFrame(.horizontal) { length, _ in length - 48 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
    }

    private func heroCard(_ album: Album, label: String) -> some View {

        NavigationLink(value: album) {
            ZStack(alignment: .bottomLeading) {
                Img(url: API.shared.img(album.image, size: ""), radius: 0)

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.45), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .kerning(0.8)
                    Text(album.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(album.artist)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(18)
                .padding(.trailing, 70)
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu { albumMenuItems(album) }
        .overlay(alignment: .bottomTrailing) {
            heroPlayButton(album)
                .padding(18)
        }
    }

    private func heroPlayButton(_ album: Album) -> some View {
        Button {
            playAlbum(album)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Play \(album.title)")
    }

    @ViewBuilder
    private func albumMenuItems(_ album: Album) -> some View {
        Button { playAlbum(album) } label: { Label("Play", systemImage: "play.fill") }
        Button { playAlbum(album, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
    }

    @ViewBuilder
    private func trackMenuItems(_ track: Track) -> some View {
        Button {
            AudioPlayer.shared.addLast(track)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: { Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") }
        Button { state.requestedTrackForPlaylist = track } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
    }

    private var topSongsChart: some View {
        let tracks = Array(state.topTracks.prefix(5))
        return VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                chartRow(rank: i + 1, track: t, queue: state.topTracks)
                if i < tracks.count - 1 {
                    Divider().padding(.leading, 116)
                }
            }
        }
        .padding(.vertical, 4)
        .nativeCard(20)
        .padding(.horizontal, 16)
    }

    private func chartRow(rank: Int, track: Track, queue: [Track]) -> some View {
        let active = state.player.current == track
        return Button {
            playTrack(track, from: queue)
        } label: {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .frame(width: 30, alignment: .center)

                ZStack {
                    AlbumArt(track: track, size: 52)
                    if active {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .frame(width: 52, height: 52)
                        Bars(color: .white).scaleEffect(0.7)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: active ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { trackMenuItems(track) }
        .accessibilityLabel("Play \(track.title) by \(track.artist), number \(rank)")
    }

    private var favoritesGrid: some View {
        let favs = Array(state.favTracks.prefix(12))
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(64), spacing: 10), GridItem(.fixed(64))], spacing: 10) {
                ForEach(favs) { t in
                    favoriteTile(t, queue: favs)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
        .frame(height: 138)
    }

    private func favoriteTile(_ track: Track, queue: [Track]) -> some View {
        let active = state.player.current == track
        return Button {
            playTrack(track, from: queue)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    AlbumArt(track: track, size: 48)
                    if active {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .frame(width: 48, height: 48)
                        Bars(color: .white).scaleEffect(0.6)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 250, height: 64)
            .nativeCard(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu { trackMenuItems(track) }
        .accessibilityLabel("Play \(track.title) by \(track.artist)")
    }

    @ViewBuilder
    private func serverSection(_ s: HomeSection) -> some View {
        section(s.title, subtitle: s.description) {
            ScrollView(.horizontal, showsIndicators: false) {

                LazyHStack(alignment: .top, spacing: 14) {

                    ForEach(Array(s.items.enumerated()), id: \.offset) { _, item in
                        homeItemCard(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    @ViewBuilder
    private func homeItemCard(_ item: HomeItem) -> some View {
        switch item {
        case .album(let a):
            NavigationLink(value: a) { AlbumCard(album: a, size: 150) }
                .buttonStyle(PressableCardStyle())
                .contextMenu { albumMenuItems(a) }
        case .artist(let a):

            NavigationLink(value: a) {
                VStack(alignment: .leading, spacing: 8) {
                    ArtistAvatar(artist: a, size: 150)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text("Artist").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                }
            }
            .buttonStyle(PressableCardStyle())
        case .playlist(let pl):
            NavigationLink(value: pl) {
                VStack(alignment: .leading, spacing: 10) {
                    PlaylistImageGrid(playlist: pl, size: 150)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pl.name).font(.system(size: 15, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                        Text("\(pl.trackcount) songs").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150)
            }
            .buttonStyle(PressableCardStyle())
        case .track(let t):
            Button { playTrack(t, from: [t]) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    AlbumArt(track: t, size: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text(t.artist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                }
            }
            .buttonStyle(PressableCardStyle())
            .contextMenu { trackMenuItems(t) }
        case .mix(let m):
            NavigationLink(value: m) {
                VStack(alignment: .leading, spacing: 8) {
                    Img(urls: mixImageURLs(m), radius: 12,
                        placeholderColor: m.extra.images?.first?.color ?? m.extra.image?.color)
                        .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text(m.extra.type.map { "\($0.capitalized) mix" } ?? "Mix").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                }
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private func mixImageURLs(_ m: Mix) -> [URL] {
        guard let file = m.imageFile else { return [] }
        return [API.shared.mixImg(file, size: "medium"), API.shared.img(file, size: "medium")].compactMap { $0 }
    }

    private func albumRail(_ albums: [Album]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(albums) { a in
                    NavigationLink(value: a) { AlbumCard(album: a, size: 150) }
                        .buttonStyle(PressableCardStyle())
                        .contextMenu { albumMenuItems(a) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
    }

    private var artistRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 18) {
                ForEach(state.allArtists.prefix(20)) { a in
                    NavigationLink(value: a) { ArtistCard(artist: a, size: 96) }
                        .buttonStyle(PressableCardStyle())
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
    }

    private var playlistRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(state.allPlaylists) { pl in
                    NavigationLink(value: pl) {
                        VStack(alignment: .leading, spacing: 10) {
                            PlaylistImageGrid(playlist: pl, size: 150)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(pl.trackcount) songs")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 150)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.house")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Pull to refresh once your server has some listening data.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 170, height: 22)
                        .padding(.horizontal, 16)
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 150, height: 150)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private func pickHeroes() -> [HeroPick] {
        var picks: [HeroPick] = []
        var used = Set<String>()
        func add(_ album: Album?, _ label: String) {
            guard let album, !used.contains(album.albumhash) else { return }
            used.insert(album.albumhash)
            picks.append(HeroPick(album: album, label: label))
        }

        add(state.recentPlayed.dropFirst(3).randomElement(), "Forgotten Favorite")
        add(state.recentAdded.first, "New in Library")
        add(state.recentPlayed.first, "Jump Back In")
        add((state.recentPlayed + state.recentAdded).randomElement(), "From Your Library")
        return Array(picks.prefix(4))
    }

    private func section<C: View>(
        _ title: String,
        subtitle: String? = nil,
        seeAll: HomeRoute? = nil,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        sectionHeader(title, subtitle: subtitle, chevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    sectionHeader(title, subtitle: subtitle, chevron: false)
                }
            }
            .padding(.horizontal, 16)
            content()
        }
    }

    private func sectionHeader(_ title: String, subtitle: String?, chevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
