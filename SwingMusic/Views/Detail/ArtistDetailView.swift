import SwiftUI

struct ArtistDetailView: View {
    let hash: String
    @EnvironmentObject var state: AppState
    @State private var detail: ArtistDetail?
    @State private var albumSections: [ArtistAlbumSection] = []
    @State private var similar: [Artist] = []
    @State private var bgImage: UIImage?
    @State private var showAllTracks = false

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

                    Color.clear.frame(height: 110)
                }
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 420)
            }
        }
        .background { AdaptiveDetailBackground(image: bgImage) }
        .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Album.self) { AlbumDetailView(hash: $0.albumhash) }
                .navigationDestination(for: Artist.self) { ArtistDetailView(hash: $0.artisthash) }
        .task { await load() }
    }

    private func heroSection(_ d: ArtistDetail) -> some View {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    ArtistAvatar(artist: d.artist, size: 160)
                        .padding(.top, 20)
                    Spacer()
                }

                Text(d.artist.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let tc = d.artist.trackcount {
                        statBadge("\(tc) Songs")
                    }
                    if let ac = d.artist.albumcount {
                        statBadge("\(ac) Albums")
                    }
                    if let dur = d.artist.duration, dur > 0 {
                        statBadge(formatDuration(dur))
                    }
                }

                HStack(spacing: 12) {
                    Button { state.player.playAll(d.tracks, source: .artist(hash)) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 150, height: 46)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(Pressed())

                    Button { state.player.playAll(d.tracks, shuffled: true, source: .artist(hash)) } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 46)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(Pressed())
                }
            }
    }

    private func topSongsList(_ d: ArtistDetail) -> some View {
        let shown = showAllTracks ? d.tracks : Array(d.tracks.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top Songs")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if d.tracks.count > 5 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showAllTracks.toggle() }
                    } label: {
                        Text(showAllTracks ? "SHOW LESS" : "SEE ALL")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                        state.player.play(t, from: d.tracks, source: .artist(hash))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func genresStrip(_ d: ArtistDetail) -> some View {
        if let genres = d.artist.genres, !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Genres")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.genrehash) { g in
                            Text(g.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(.white.opacity(0.1), in: Capsule())
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
                    HStack {
                        Text(section.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(section.albums.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 18)

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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
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

    private func statCard(_ stat: ArtistStat, color: String?) -> some View {
        let base = color.flatMap { Color(rgbString: $0) } ?? .blue
        let fg = textColor(forRGB: color)
        return VStack(alignment: .leading, spacing: 8) {
            if let image = stat.image, !image.isEmpty {
                Img(url: API.shared.img(image, size: "small"), radius: 8)
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: statIcon(stat.cssclass))
                    .font(.system(size: 20))
                    .foregroundStyle(fg.opacity(0.9))
                    .frame(width: 40, height: 40)
            }
            Text(stat.value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(fg)
                .lineLimit(1)
            Text(stat.text)
                .font(.system(size: 12))
                .foregroundStyle(fg.opacity(0.6))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 160, height: 160, alignment: .topLeading)
        .background(base)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
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
            Text("Similar Artists")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

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
            .foregroundStyle(.white.opacity(0.8))
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
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let img = UIImage(data: data) else { return }
        bgImage = img
    }
}
