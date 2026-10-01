import SwiftUI

struct DetailPlayButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 160)
            }
            .buttonStyle(.glassProminent)

            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 160)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
    }
}

struct DetailScrollTitle: ViewModifier {
    let title: String
    let threshold: CGFloat
    @State private var shows = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > threshold
            } action: { _, now in
                withAnimation(.easeInOut(duration: 0.2)) { shows = now }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(shows ? 1 : 0)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func detailScrollTitle(_ title: String, after threshold: CGFloat) -> some View {
        modifier(DetailScrollTitle(title: title, threshold: threshold))
    }
}

struct DetailFooter: View {
    var date: String?
    let songCount: Int
    let totalSeconds: Int
    var copyright: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date { Text(date) }
            Text("\(songCount) \(songCount == 1 ? "Song" : "Songs"), \(Self.duration(totalSeconds))")
            if let copyright, !copyright.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(copyright)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    static func duration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(max(1, m)) minutes"
    }
}
