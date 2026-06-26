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
            loading = false
            await loadBg()
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Img(urls: imageURLs("medium"), radius: 14, placeholderColor: mix.extra.images?.first?.color ?? mix.extra.image?.color)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text(mix.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text([mix.extra.type.map { "\($0.capitalized) mix" } ?? "Mix",
                      mix.trackcount.map { "\($0) songs" }].compactMap { $0 }.joined(separator: " · "))
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
