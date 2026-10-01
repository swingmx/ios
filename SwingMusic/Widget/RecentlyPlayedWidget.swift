import SwiftUI
import WidgetKit

struct RecentEntry: TimelineEntry {
    let date: Date
    let tracks: [RecentTrack]

    static let preview = RecentEntry(
        date: .now,
        tracks: [
            RecentTrack(title: "Midnight City", artist: "M83", imageData: nil, accentHex: "#8E44AD"),
            RecentTrack(title: "Blinding Lights", artist: "The Weeknd", imageData: nil, accentHex: "#E74C3C"),
            RecentTrack(title: "Levitating", artist: "Dua Lipa", imageData: nil, accentHex: "#3498DB"),
            RecentTrack(title: "Heat Waves", artist: "Glass Animals", imageData: nil, accentHex: "#1ABC9C"),
        ]
    )
}

struct RecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        completion(context.isPreview ? .preview : readHistory())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        completion(Timeline(entries: [readHistory()], policy: .after(Date().addingTimeInterval(60))))
    }

    private func readHistory() -> RecentEntry {
        guard let d = UserDefaults(suiteName: "group.swingmusic"),
              let data = d.data(forKey: "w.history"),
              let tracks = try? JSONDecoder().decode([RecentTrack].self, from: data)
        else { return RecentEntry(date: .now, tracks: []) }
        return RecentEntry(date: .now, tracks: tracks)
    }
}

struct ArtTile: View {
    let track: RecentTrack
    let size: CGFloat
    let radius: CGFloat

    var accent: Color { Color(hex: track.accentHex) ?? .gray }

    var body: some View {
        Color.clear.frame(width: size, height: size).overlay {
            if let d = track.imageData, let img = UIImage(data: d) {
                Image(uiImage: img)
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.7), accent.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct RecentEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing played yet")
                .font(.footnote.weight(.semibold))
            Text("Songs you play appear here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecentHeader: View {
    var body: some View {
        Label("Recently Played", systemImage: "clock.arrow.circlepath")
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.accentColor)
            .widgetAccentable()
    }
}

struct RecentSmallView: View {
    let entry: RecentEntry

    var body: some View {
        Group {
        if let track = entry.tracks.first {
        GeometryReader { geo in
            let w = geo.size.width
            let artSize = min(w, geo.size.height - 38)

            VStack(alignment: .leading, spacing: 8) {
                ArtTile(track: track, size: artSize, radius: 12)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        } else {
            RecentEmptyView()
        }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct RecentMediumView: View {
    let entry: RecentEntry

    var body: some View {
        let tracks = Array(entry.tracks.prefix(4))

        GeometryReader { geo in
            let spacing: CGFloat = 10
            let hPad: CGFloat = 16
            let availableW = geo.size.width - hPad * 2 - spacing * 3
            let tileSize = floor(availableW / 4)

            VStack(alignment: .leading, spacing: 8) {
                RecentHeader()

                HStack(spacing: spacing) {
                    ForEach(tracks.indices, id: \.self) { i in
                        let t = tracks[i]
                        VStack(alignment: .leading, spacing: 4) {
                            ArtTile(track: t, size: tileSize, radius: 8)
                            Text(t.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Text(t.artist)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: tileSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct RecentLargeView: View {
    let entry: RecentEntry

    var body: some View {
        let tracks = Array(entry.tracks.prefix(4))

        GeometryReader { geo in
            let spacing: CGFloat = 12
            let hPad: CGFloat = 16
            let availableW = geo.size.width - hPad * 2 - spacing
            let tileSize = floor(availableW / 2)
            let artSize = tileSize - 10

            VStack(alignment: .leading, spacing: 12) {
                RecentHeader()

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: spacing),
                    GridItem(.flexible(), spacing: spacing)
                ], spacing: 14) {
                    ForEach(tracks.indices, id: \.self) { i in
                        let t = tracks[i]
                        VStack(alignment: .leading, spacing: 6) {
                            ArtTile(track: t, size: artSize, radius: 10)
                                .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(t.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

private func paddedTracks(_ tracks: [RecentTrack], count: Int) -> [RecentTrack] {
    if tracks.count >= count { return Array(tracks.prefix(count)) }
    let fallbacks = RecentEntry.preview.tracks
    var result = tracks
    while result.count < count {
        result.append(fallbacks[result.count % fallbacks.count])
    }
    return result
}

struct RecentlyPlayedWidget: Widget {
    let kind = "SwingMusicRecentlyPlayed"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentProvider()) { entry in
            RecentlyPlayedEntryView(entry: entry)
        }
        .configurationDisplayName("Recently Played")
        .description("Your latest tracks at a glance")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentlyPlayedEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: RecentEntry

    var body: some View {
        if entry.tracks.isEmpty {
            RecentEmptyView()
                .containerBackground(for: .widget) { Color(.systemBackground) }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall: RecentSmallView(entry: entry)
        case .systemMedium: RecentMediumView(entry: entry)
        case .systemLarge: RecentLargeView(entry: entry)
        default: RecentMediumView(entry: entry)
        }
    }
}
