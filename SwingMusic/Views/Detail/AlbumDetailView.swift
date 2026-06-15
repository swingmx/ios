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
                    Color.clear.frame(height: 100)
                }
            } else {
                VStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .frame(minHeight: 400)
            }
        }
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
                Text(d.info.artist)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let dt = d.info.date { Text(Date(timeIntervalSince1970: TimeInterval(dt)).formatted(.dateTime.year())) }
                    if let tc = d.info.trackcount { Text("·"); Text("\(tc) songs") }
                    if let dur = d.info.duration { Text("·"); Text(dur.mmss) }
                }
                .font(.system(size: 13)).foregroundStyle(.tertiary)
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
            .padding(.top, 4).padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private func trackList(_ d: AlbumDetail) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(d.tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, num: t.trackno ?? (i + 1), active: state.player.current == t, showArt: false) {
                    state.player.play(t, from: d.tracks)
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
