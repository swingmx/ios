import SwiftUI

struct ArtistDetailView: View {
    let hash: String
    @EnvironmentObject var state: AppState
    @State private var detail: ArtistDetail?
    @State private var albumSections: [ArtistAlbumSection] = []
    @State private var similar: [Artist] = []
    @State private var bgImage: UIImage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let d = detail {
                VStack(spacing: 24) {
                    heroSection(d)
                    topSongsList(d)

                    ForEach(albumSections, id: \.self) { section in
                        albumsSection(section)
                    }

                    genresStrip(d)

                    if !similar.isEmpty {
                        similarArtistsSection
                    }

                    if let stats = d.stats, !stats.isEmpty {
                        statsSection(stats, color: d.artist.color)
                    }

                    ArtistAboutSection(artistName: d.artist.name, hint: d.tracks.first?.title)

                    Color.clear.frame(height: 110)
                }
            } else {
                ProgressView().tint(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 420)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AdaptiveDetailBackground(image: bgImage) }
        .detailScrollTitle(detail?.artist.name ?? "", after: 380)
                .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
                .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
                .navigationDestination(for: ArtistAlbumSection.self) { section in
                    ArtistAlbumsGridView(title: section.title, albums: section.albums)
                }
        .task { await load() }
    }

    private func heroSection(_ d: ArtistDetail) -> some View {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let minY = geo.frame(in: .scrollView).minY
                    ArtistAvatar(artist: d.artist, size: 170)
                        .shadow(color: (d.artist.color.flatMap { Color(rgbString: $0) } ?? .black).opacity(0.55),
                                radius: 34, y: 12)
                        .scaleEffect(minY > 0 ? 1 + minY / 600 : 1 + minY / 2400, anchor: .bottom)
                        .offset(y: minY > 0 ? -minY * 0.3 : -minY * 0.2)
                        .opacity(minY < 0 ? max(0.25, 1 + minY / 500) : 1)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 170)
                .padding(.top, 20)

                Text(d.artist.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(statsLine(d.artist))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DetailPlayButtons(
                    play: { state.player.playAll(d.tracks, source: .artist(hash)) },
                    shuffle: { state.player.playAll(d.tracks, shuffled: true, source: .artist(hash)) }
                )
            }
    }

    private func topSongsList(_ d: ArtistDetail) -> some View {
        let total = d.artist.trackcount ?? d.tracks.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Songs")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Spacer()
                if total > 5 {
                    NavigationLink {
                        ArtistTracksView(hash: hash, artistName: d.artist.name)
                    } label: {
                        Text("See All").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(d.tracks.prefix(5).enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                        state.player.play(t, from: d.tracks, source: .artist(hash))
                    }
                }
            }
        }
    }

    private func sectionHeaderLabel(_ title: String, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .contentShape(.rect)
    }

    @ViewBuilder
    private func genresStrip(_ d: ArtistDetail) -> some View {
        if let genres = d.artist.genres, !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeaderLabel("Genres", showsChevron: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.genrehash) { g in
                            Text(g.name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return m > 0 ? "\(h) hr \(m) min" : "\(h) hr" }
        if m > 0 { return "\(m) min" }
        return "\(seconds) sec"
    }

    private func albumsSection(_ section: ArtistAlbumSection) -> some View {
        Group {
            if !section.albums.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if section.albums.count > 3 {
                        NavigationLink(value: section) {
                            sectionHeaderLabel(section.title, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        sectionHeaderLabel(section.title, showsChevron: false)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(section.albums) { a in
                                NavigationLink(value: a) {
                                    AlbumCard(album: a, size: 140)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
    }

    private func statsSection(_ stats: [ArtistStat], color: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stats, id: \.self) { stat in
                        statCard(stat, color: color)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func statsLine(_ a: Artist) -> String {
        var parts: [String] = []
        if let tc = a.trackcount { parts.append("\(tc) \(tc == 1 ? "Song" : "Songs")") }
        if let ac = a.albumcount { parts.append("\(ac) \(ac == 1 ? "Album" : "Albums")") }
        if let dur = a.duration, dur > 0 { parts.append(DetailFooter.duration(dur)) }
        return parts.joined(separator: " · ")
    }

    private func statCard(_ stat: ArtistStat, color: String?) -> some View {
        let accent = color.flatMap { Color(rgbString: $0) } ?? .accentColor
        return VStack(alignment: .leading, spacing: 0) {
            if let image = stat.image, !image.isEmpty {
                Img(url: API.shared.img(image, size: "small"), radius: 6)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: statIcon(stat.cssclass))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(accent.gradient, in: .circle)
            }
            Spacer(minLength: 12)
            Text(stat.value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 150, height: 130, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func statIcon(_ cssclass: String) -> String {
        switch cssclass {
        case "play_duration": "clock.fill"
        case "played": "play.circle.fill"
        case "toptrack": "music.note"
        case "topalbum": "square.stack.fill"
        default: "chart.bar.fill"
        }
    }

    private func textColor(forRGB rgb: String?) -> Color {
        guard let rgb else { return .white }
        let nums = rgb
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 3 else { return .white }
        let lum = (0.299 * nums[0] + 0.587 * nums[1] + 0.114 * nums[2]) / 255
        return lum > 0.62 ? .black : .white
    }

    private var similarArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeaderLabel("Similar Artists", showsChevron: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(similar) { a in
                        NavigationLink(value: a) {
                            ArtistCard(artist: a, size: 110)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func statBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func load() async {
        detail = try? await API.shared.artist(hash)
        albumSections = (try? await API.shared.artistAlbums(hash)) ?? []
        similar = (try? await API.shared.similarArtists(hash)) ?? []
        if let imagePath = detail?.artist.image {
            await loadBackgroundImage(path: imagePath)
        }
    }

    private func loadBackgroundImage(path: String) async {
        guard let url = API.shared.artistImg(path, size: "") else { return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token {
            req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await Net.session.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let img = UIImage(data: data) else { return }
        bgImage = img
    }
}

struct ArtistTracksView: View {
    let hash: String
    let artistName: String
    @EnvironmentObject var state: AppState
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if loading && tracks.isEmpty {
                ProgressView().tint(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else if tracks.isEmpty {
                Text("Couldn't load songs")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                            state.player.play(t, from: tracks, source: .artist(hash))
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard tracks.isEmpty else { return }
            tracks = (try? await API.shared.artistTracks(hash)) ?? []
            loading = false
        }
    }
}

struct ArtistAlbumsGridView: View {
    let title: String
    let albums: [Album]
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 18) {
                ForEach(albums) { a in
                    NavigationLink(value: a) { AlbumCard(album: a, size: 150) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
    }
}
