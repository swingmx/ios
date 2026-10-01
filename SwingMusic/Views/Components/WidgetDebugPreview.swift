#if DEBUG
import SwiftUI

struct WidgetDebugPreview: View {
    @State private var art: Data?

    var body: some View {
        let entry = MusicEntry(date: .now, title: "Blue Plastic", artist: "Yung Lean", album: "Blue Plastic",
                               playing: true, progress: 52, progressAt: .now, duration: 173,
                               imageData: art, accentHex: "#5E5CE6")
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    tile(SmallWidget(entry: entry), w: 170, h: 170, art: art)
                    tile(SmallWidget(entry: entry), w: 170, h: 170, art: nil)
                }
                tile(MediumWidget(entry: entry), w: 364, h: 170, art: art)
                tile(LargeWidget(entry: entry), w: 364, h: 382, art: art)
            }
            .padding(.vertical, 20)
        }
        .background(Color(white: 0.35))
        .task {
            let hits = (try? await API.shared.search("Blue Plastic"))?.tracks ?? []
            guard let t = hits.first, let url = API.shared.img(t.image, size: "large") else { return }
            var r = URLRequest(url: url)
            if let tk = API.shared.token { r.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
            art = try? await Net.session.data(for: r).0
        }
    }

    private func tile<V: View>(_ v: V, w: CGFloat, h: CGFloat, art: Data?) -> some View {
        ZStack {
            ArtworkBackdrop(data: art)
            v.padding(16)
        }
        .frame(width: w, height: h)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}
#endif
