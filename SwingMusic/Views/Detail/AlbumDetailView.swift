import SwiftUI

struct AlbumDetailView: View {
    let hash: String
    @Environment(AppState.self) var state
    @State private var detail: AlbumDetail?
    @State private var loading = true
    @State private var bgImage: UIImage?
    @State private var isOfflineCopy = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let d = detail {
                VStack(spacing: 0) {
                    header(d)
                    trackList(d)
                    DetailFooter(
                        date: d.info.date.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .long, time: .omitted) },
                        songCount: d.tracks.count,
                        totalSeconds: d.info.duration ?? d.tracks.reduce(0) { $0 + $1.duration },
                        copyright: d.info.copyright
                    )
                    // Saved stats are frozen at download time, so they are only shown live.
                    if !isOfflineCopy, let stats = d.stats, !stats.isEmpty {
                        StatsRow(stats: stats, color: d.info.color)
                            .padding(.top, 28)
                    }
                    Color.clear.frame(height: 100)
                }
            } else {
                VStack { Spacer(); ProgressView().tint(.secondary); Spacer() }
                    .frame(minHeight: 400)
            }
        }
        .squeezeMiniPlayer(state)
        .detailBackground(bgImage)
        .detailScrollTitle(detail?.info.title ?? "", after: 330)
        .toolbar {
            if let d = detail {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    FavoriteButton(isFavorite: state.isAlbumFavorite(d.info)) {
                        let album = d.info
                        Task { await state.setAlbumFavorite(album, !state.isAlbumFavorite(album)) }
                    }
                    CollectionActionsMenu(
                        tracks: sortedTracks(d.tracks),
                        group: DownloadManager.DownloadGroup(
                            id: "album:\(hash)", kind: .album, name: d.info.title,
                            image: d.info.image, trackHashes: d.tracks.map { $0.trackhash })
                    )
                }
            }
        }
        .environment(\.leavesAfterDownloadRemoval, isOfflineCopy)
        .task { await load() }
    }

    private func header(_ d: AlbumDetail) -> some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let minY = geo.frame(in: .scrollView).minY
                AlbumCover(album: d.info, size: coverSize)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                    .scaleEffect(minY > 0 ? 1 + minY / 600 : 1 + minY / 2400, anchor: .bottom)
                    .offset(y: minY > 0 ? -minY * 0.3 : -minY * 0.2)
                    .opacity(minY < 0 ? max(0.25, 1 + minY / 500) : 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: coverSize)
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(d.info.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .explicitBadge(d.tracks.contains { $0.isExplicit })
                Button {
                    let a = d.info.albumartists?.first
                    state.navigationTarget = .artist(Artist(stub: a?.artisthash ?? d.info.artisthash, name: a?.name ?? d.info.artist, image: d.info.image))
                } label: {
                    Text(d.info.artist)
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
                Text(subtitleLine(d))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            DetailPlayButtons(
                play: { state.player.playAll(sortedTracks(d.tracks), source: .album(hash)) },
                shuffle: { state.player.playAll(sortedTracks(d.tracks), shuffled: true, source: .album(hash)) }
            )
            .padding(.top, 4).padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private var coverSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 320 : 270
    }

    private func subtitleLine(_ d: AlbumDetail) -> String {
        var parts: [String] = []
        if let g = d.tracks.lazy.compactMap({ $0.genres?.first?.name }).first, !g.isEmpty { parts.append(g) }
        if let dt = d.info.date { parts.append(Date(timeIntervalSince1970: TimeInterval(dt)).formatted(.dateTime.year())) }
        return parts.joined(separator: " · ")
    }

    private func sortedTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { a, b in
            let da = a.disc ?? 1, db = b.disc ?? 1
            if da != db { return da < db }
            return (a.trackno ?? 0) < (b.trackno ?? 0)
        }
    }

    private func trackList(_ d: AlbumDetail) -> some View {
        let ordered = sortedTracks(d.tracks)
        let discs = Set(ordered.map { $0.disc ?? 1 })
        let multiDisc = discs.count > 1
        return VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { i, t in
                let disc = t.disc ?? 1
                let isFirstOfDisc = i == 0 || (ordered[i - 1].disc ?? 1) != disc
                if multiDisc && isFirstOfDisc {
                    HStack(spacing: 8) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 13))
                        Text("Disc \(disc)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, i == 0 ? 8 : 24)
                    .padding(.bottom, 8)
                }
                TrackRow(track: t, num: t.trackno ?? (i + 1), active: state.isCurrentTrack(t), showArt: false) {
                    state.player.play(t, from: ordered, source: .album(hash))
                }
            }
        }
        .environment(\.trackListContext, .album(hash))
    }

    private func load() async {
        if let d = try? await API.shared.album(hash) {
            detail = d
        } else {
            let dl = DownloadManager.shared.downloadedTracks.filter { $0.albumhash == hash }
            if let t = dl.first {
                detail = AlbumDetail(
                    info: Album(stub: hash, title: t.album, image: t.image, date: t.date, albumartists: t.albumartists),
                    tracks: dl)
                isOfflineCopy = true
            }
        }
        loading = false
        await loadBgImage()
    }

    private func loadBgImage() async {
        guard let image = detail?.info.image,
              let url = API.shared.img(image) else { return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await Net.session.data(for: req),
              let img = UIImage(data: data) else { return }
        bgImage = img
    }
}
