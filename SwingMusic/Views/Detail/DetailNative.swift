import SwiftUI

struct DetailPlayButtons: View {
    let play: () -> Void
    let shuffle: () -> Void
    @Environment(\.detailTint) private var tint

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 160)
                    .foregroundStyle(tint == nil ? Color.white : Color.black.opacity(0.85))
            }
            .buttonStyle(.glassProminent)
            .tint(tint)

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

// The "Stats" row on artist and album screens: listening stats the server computes for a group of tracks.
struct StatsRow: View {
    let stats: [ArtistStat]
    // Tints stat icons; the screen's artist or album color.
    let color: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stats, id: \.self) { stat in
                        card(stat)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func card(_ stat: ArtistStat) -> some View {
        let accent = color.flatMap { Color(rgbString: $0) } ?? .accentColor
        return VStack(alignment: .leading, spacing: 0) {
            if let image = stat.image, !image.isEmpty {
                Img(url: API.shared.img(image, size: "small"), radius: 6)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: Self.icon(stat.cssclass))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(accent.gradient, in: .circle)
            }
            Spacer(minLength: 12)
            Text(stat.value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 150, height: 130, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    static func icon(_ cssclass: String) -> String {
        switch cssclass {
        case "play_duration": "clock.fill"
        case "played": "play.circle.fill"
        case "toptrack": "music.note"
        case "topalbum": "square.stack.fill"
        case "completeness": "checkmark.circle.fill"
        default: "chart.bar.fill"
        }
    }
}
