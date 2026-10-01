import SwiftUI

struct PlaylistDetailView: View {
    let id: String
    let name: String
    @EnvironmentObject var state: AppState
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var bgImage: UIImage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                    .padding(.top, 40)

                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                            state.player.play(t, from: tracks, source: .playlist(id))
                        }
                    }
                }
                .padding(.top, 24)

                if !tracks.isEmpty {
                    DetailFooter(songCount: tracks.count, totalSeconds: tracks.reduce(0) { $0 + $1.duration })
                }
                Color.clear.frame(height: 100)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AdaptiveDetailBackground(image: bgImage) }
        .detailScrollTitle(name, after: 300)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DownloadControl(tracks: tracks, group: DownloadManager.DownloadGroup(
                    id: "playlist:\(id)", kind: .playlist, name: name,
                    image: tracks.first?.image ?? "", trackHashes: tracks.map { $0.trackhash }))
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let minY = geo.frame(in: .scrollView).minY
                PlaylistImageGrid(playlist: state.allPlaylists.first { $0.id == id }, size: coverSize)
                    .scaleEffect(minY > 0 ? 1 + minY / 600 : 1 + minY / 2400, anchor: .bottom)
                    .offset(y: minY > 0 ? -minY * 0.3 : -minY * 0.2)
                    .opacity(minY < 0 ? max(0.25, 1 + minY / 500) : 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: coverSize)
            .padding(.top, 16)

            Text(name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Playlist")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            DetailPlayButtons(
                play: { state.player.playAll(tracks, source: .playlist(id)) },
                shuffle: { state.player.playAll(tracks, shuffled: true, source: .playlist(id)) }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var coverSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 300 : 250
    }

    private func load() async {
        if let d = try? await API.shared.playlist(id) {
            tracks = d.tracks
            await loadBgImage(p: d.info)
        } else if let group = DownloadManager.shared.downloadGroups.first(where: { $0.id == "playlist:\(id)" }) {
            tracks = DownloadManager.shared.tracks(in: group)
        }
        loading = false
    }

    private func loadBgImage(p: Playlist) async {
        var hashes: [String] = []
        if let img = p.image, img != "None", !img.isEmpty { hashes.append(img) }
        hashes += (p.images ?? []).compactMap { $0.image }.filter { $0 != "None" && !$0.isEmpty }
        if hashes.count < 4 {
            hashes += tracks.map { $0.image }.filter { !$0.isEmpty }
        }
        var seen = Set<String>()
        let unique = hashes.filter { seen.insert($0).inserted }.prefix(9)
        guard !unique.isEmpty else { return }

        let images = await withTaskGroup(of: (Int, UIImage)?.self) { group -> [UIImage] in
            for (i, h) in unique.enumerated() {
                group.addTask {
                    guard let url = API.shared.img(h, size: "small") else { return nil }
                    var req = URLRequest(url: url)
                    if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
                    guard let (data, _) = try? await Net.session.data(for: req),
                          let img = UIImage(data: data) else { return nil }
                    return (i, img)
                }
            }
            var collected: [(Int, UIImage)] = []
            for await r in group { if let r { collected.append(r) } }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        guard let mosaic = Self.mosaic(images) else { return }
        withAnimation { bgImage = mosaic }
    }

    static func mosaic(_ images: [UIImage], side: CGFloat = 600) -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images[0] }
        let cols = images.count <= 4 ? 2 : 3
        let rows = Int(ceil(Double(images.count) / Double(cols)))
        let cell = side / CGFloat(cols)
        let height = cell * CGFloat(rows)
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: height))
        return r.image { _ in
            for (i, img) in images.enumerated() {
                let x = CGFloat(i % cols) * cell
                let y = CGFloat(i / cols) * cell
                img.draw(in: CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
    }
}
