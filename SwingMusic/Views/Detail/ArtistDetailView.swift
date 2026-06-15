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
                    topSongsCards(d)
                    trackListSection(d)

                    ForEach(albumSections, id: \.self) { section in
                        albumsSection(section)
                    }

                    if !similar.isEmpty {
                        similarArtistsSection
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
                }

                HStack(spacing: 12) {
                    Button { state.player.playAll(d.tracks) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 150, height: 46)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(Pressed())

                    Button { state.player.playAll(d.tracks, shuffled: true) } label: {
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

    private func topSongsCards(_ d: ArtistDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Songs")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(d.tracks.prefix(10).enumerated()), id: \.element.id) { i, t in
                        Button {
                            state.player.play(t, from: d.tracks)
                        } label: {
                            songCard(track: t, rank: i + 1, active: state.player.current == t)
                        }
                        .buttonStyle(Pressed())
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func songCard(track: Track, rank: Int, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .overlay {
                        Img(url: API.shared.img(track.image, size: "medium"), radius: 0)
                    }
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("\(rank)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4, y: 2)
                    .padding(8)
            }

            Text(track.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.top, 8)

            Text(track.duration.mmss)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
        .frame(width: 130)
    }

    private func trackListSection(_ d: ArtistDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Tracks")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    state.player.playAll(Array(d.tracks.prefix(10)))
                } label: {
                    Text("Play Top 10")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(d.tracks.prefix(10).enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                        state.player.play(t, from: d.tracks)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
        }
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
