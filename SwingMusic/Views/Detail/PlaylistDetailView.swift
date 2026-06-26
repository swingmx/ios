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

                Color.clear.frame(height: 100)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AdaptiveDetailBackground(image: bgImage) }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let minY = geo.frame(in: .scrollView).minY
                PlaylistImageGrid(playlist: state.allPlaylists.first { $0.id == id }, size: 180)
                    .scaleEffect(max(1, 1 + minY / 600))
                    .offset(y: minY > 0 ? -minY * 0.3 : 0)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 180)
            .padding(.top, 16)

            Text(name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text("\(tracks.isEmpty ? "..." : "\(tracks.count)") songs")
                .font(.system(size: 13)).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button { state.player.playAll(tracks, source: .playlist(id)) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(Pressed())

                Button { state.player.playAll(tracks, shuffled: true, source: .playlist(id)) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(Pressed())

                DownloadControl(tracks: tracks, group: DownloadManager.DownloadGroup(
                    id: "playlist:\(id)", kind: .playlist, name: name,
                    image: tracks.first?.image ?? "", trackHashes: tracks.map { $0.trackhash }))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func load() async {
        if let d = try? await API.shared.playlist(id) {
            tracks = d.tracks
            await loadBgImage(p: d.info)
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
                    guard let (data, _) = try? await URLSession.shared.data(for: req),
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
