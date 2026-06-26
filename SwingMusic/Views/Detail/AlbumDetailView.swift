import SwiftUI

struct AlbumDetailView: View {
    let hash: String
    @EnvironmentObject var state: AppState
    @State private var detail: AlbumDetail?
    @State private var loading = true
    @State private var bgImage: UIImage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let d = detail {
                VStack(spacing: 0) {
                    header(d)
                    trackList(d)
                    if let cr = d.info.copyright, !cr.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(cr.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                    }
                    Color.clear.frame(height: 100)
                }
            } else {
                VStack { Spacer(); ProgressView().tint(.secondary); Spacer() }
                    .frame(minHeight: 400)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AdaptiveDetailBackground(image: bgImage) }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func header(_ d: AlbumDetail) -> some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let minY = geo.frame(in: .scrollView).minY
                AlbumCover(album: d.info, size: 220)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                    .scaleEffect(max(1, 1 + minY / 600))
                    .offset(y: minY > 0 ? -minY * 0.3 : 0)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 220)
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(d.info.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Button {
                    let a = d.info.albumartists?.first
                    state.navigationTarget = .artist(Artist(stub: a?.artisthash ?? d.info.artisthash, name: a?.name ?? d.info.artist, image: d.info.image))
                } label: {
                    Text(d.info.artist)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    if let dt = d.info.date { Text(Date(timeIntervalSince1970: TimeInterval(dt)).formatted(.dateTime.year())) }
                    if let tc = d.info.trackcount { Text("·"); Text("\(tc) songs") }
                    if let dur = d.info.duration { Text("·"); Text(dur.mmss) }
                }
                .font(.system(size: 13)).foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button { state.player.playAll(sortedTracks(d.tracks), source: .album(hash)) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(Pressed())

                Button { state.player.playAll(sortedTracks(d.tracks), shuffled: true, source: .album(hash)) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(Pressed())

                DownloadControl(tracks: d.tracks, group: DownloadManager.DownloadGroup(
                    id: "album:\(hash)", kind: .album, name: d.info.title,
                    image: d.info.image, trackHashes: d.tracks.map { $0.trackhash }))
            }
            .padding(.top, 4).padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
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
                TrackRow(track: t, num: t.trackno ?? (i + 1), active: state.player.current == t, showArt: false) {
                    state.player.play(t, from: ordered, source: .album(hash))
                }
            }
        }
    }

    private func load() async {
        detail = try? await API.shared.album(hash)
        loading = false
        await loadBgImage()
    }

    private func loadBgImage() async {
        guard let image = detail?.info.image,
              let url = API.shared.img(image) else { return }
        var req = URLRequest(url: url)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        bgImage = img
    }
}
