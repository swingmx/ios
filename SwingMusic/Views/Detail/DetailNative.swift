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
            .buttonStyle(DetailButtonStyle(prominent: true))

            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 160)
            }
            .buttonStyle(DetailButtonStyle(prominent: false))
        }
        .padding(.horizontal, 20)
    }
}

// The fill for cards and pills on album and artist screens. Solid rather than glass for the same
// reason as DetailButtonStyle: glass showed as grey in the app switcher.
enum DetailCardFill {
    static let color = Color.primary.opacity(0.08)
}

// Solid capsules rather than glass, like Apple Music's. Glass is drawn live from the content behind
// it, which iOS stops doing for the app switcher snapshot: the buttons showed as grey there and faded
// back to blue on return.
private struct DetailButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.blue)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(prominent ? Color.blue : Color.primary.opacity(0.1), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
        let accent = color.flatMap { Color(rgbString: $0) } ?? .appAccent
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
        .background(DetailCardFill.color, in: .rect(cornerRadius: 20))
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
