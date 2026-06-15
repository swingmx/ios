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

    private var isLoading: Bool {
        state.recentPlayed.isEmpty && state.recentAdded.isEmpty
            && state.topTracks.isEmpty && state.allPlaylists.isEmpty
    }

    var body: some View {
        NavigationStack(path: $state.homePath) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    Color.clear.frame(height: 0)
                        .trackScrollOffset(in: "homeScroll") { state.updateScroll($0) }

                    if isLoading {
                        skeleton
                    } else {
                        if !heroes.isEmpty {
                            heroCarousel
                        }
                        if !state.recentPlayed.isEmpty {
                            section("Recently Played") { albumRail(state.recentPlayed) }
                        }
                        if !state.topTracks.isEmpty {
                            section("Top Songs", subtitle: "Your most played this month") {
                                topSongsChart
                            }
                        }
                        if !state.favTracks.isEmpty {
                            section("Favorites") { favoritesGrid }
                        }
                        if !state.recentAdded.isEmpty {
                            section("Recently Added", seeAll: .allAlbums) { albumRail(state.recentAdded) }
                        }
                        if !state.allArtists.isEmpty {
                            section("Artists", seeAll: .allArtists) { artistRail }
                        }
                        if !state.allPlaylists.isEmpty {
                            section("Playlists") { playlistRail }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.top, 12)
            }
            .coordinateSpace(name: "homeScroll")
            .background { AmbientBackground() }
            .navigationTitle("Listening Now")
            .refreshable {
                await state.loadHome()
                await state.loadFavorites()
                heroes = pickHeroes()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
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
        }
        .task {
            if state.recentAdded.isEmpty { await state.loadHome() }
            if heroes.isEmpty { heroes = pickHeroes() }
            async let artists: Void = state.loadArtists()
            async let favs: Void = state.loadFavorites()
            _ = await (artists, favs)
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

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 360)
                .padding(.horizontal, 24)

            ForEach(0..<2, id: \.self) { _ in
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
