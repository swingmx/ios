import SwiftUI

struct MixDetailView: View {
    let mix: Mix
    @EnvironmentObject var state: AppState
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var bgImage: UIImage?

    private var source: AudioPlayer.PlaySource { .mix(id: mix.id, sourcehash: mix.sourcehash) }

    private func imageURLs(_ size: String) -> [URL] {
        guard let file = mix.imageFile else { return [] }
        return [API.shared.mixImg(file, size: size), API.shared.img(file, size: size)].compactMap { $0 }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if loading && tracks.isEmpty {
                    ProgressView().tint(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                            state.player.play(t, from: tracks, source: source)
                        }
                    }
                }
                Color.clear.frame(height: 100)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AdaptiveDetailBackground(image: bgImage) }
        .navigationTitle(mix.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = (try? await API.shared.mixTracks(id: mix.id, sourcehash: mix.sourcehash, ogSourcehash: mix.ogSourcehash)) ?? []
            if tracks.isEmpty, let group = DownloadManager.shared.downloadGroups.first(where: { $0.id == "mix:\(mix.id)" }) {

                tracks = DownloadManager.shared.tracks(in: group)
            }
            loading = false
            await loadBg()
        }
    }

    private var totalDuration: Int { tracks.reduce(0) { $0 + $1.duration } }

    private func durationText(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h) hr \(m) min" : "\(h) hr" }
        if m > 0 { return "\(m) min" }
        return "\(s) sec"
    }

    private var metaLine: String {
        let count = tracks.isEmpty ? (mix.trackcount ?? 0) : tracks.count
        var parts = ["\(count) song\(count == 1 ? "" : "s")"]
        if totalDuration > 0 { parts.append(durationText(totalDuration)) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(spacing: 16) {

            Text(mix.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Img(urls: imageURLs("medium"), radius: 14, placeholderColor: mix.extra.images?.first?.color ?? mix.extra.image?.color)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)

            VStack(spacing: 6) {
                if let tag = mix.tagline, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                Text(metaLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { state.player.playAll(tracks, source: source) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(Pressed())
                .disabled(tracks.isEmpty)

                Button { state.player.playAll(tracks, shuffled: true, source: source) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(Pressed())
                .disabled(tracks.isEmpty)

                if !tracks.isEmpty {
                    DownloadControl(tracks: tracks, group: DownloadManager.DownloadGroup(
                        id: "mix:\(mix.id)", kind: .mix, name: mix.title,
                        image: "", trackHashes: tracks.map { $0.trackhash }))
                }
            }
            .padding(.top, 4).padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private func loadBg() async {
        for url in imageURLs("medium") {
            var req = URLRequest(url: url)
            if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
            if let (data, _) = try? await URLSession.shared.data(for: req), let img = UIImage(data: data) {
                bgImage = img
                return
            }
        }
    }
}
