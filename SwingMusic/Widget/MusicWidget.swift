import AppIntents
import SwiftUI
import WidgetKit

struct MusicEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let playing: Bool
    let progress: Double
    let duration: Double
    let imageData: Data?
    let accentHex: String

    static let preview = MusicEntry(
        date: .now,
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        playing: true,
        progress: 72,
        duration: 244,
        imageData: nil,
        accentHex: "#FF375F"
    )
}

struct MusicProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(30))))
    }

    private func read() -> MusicEntry {
        let d = UserDefaults(suiteName: "group.swingmusic")
        return MusicEntry(
            date: .now,
            title: d?.string(forKey: "w.title") ?? "Not Playing",
            artist: d?.string(forKey: "w.artist") ?? "-",
            album: d?.string(forKey: "w.album") ?? "",
            playing: d?.bool(forKey: "w.playing") ?? false,
            progress: d?.double(forKey: "w.progress") ?? 0,
            duration: d?.double(forKey: "w.duration") ?? 0,
            imageData: d?.data(forKey: "w.image"),
            accentHex: d?.string(forKey: "w.accent") ?? "#FF375F"
        )
    }
}

struct SmallWidget: View {
    let entry: MusicEntry
    var accent: Color { Color(hex: entry.accentHex) ?? .pink }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                wArt(entry.imageData, size: 44, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(entry.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.84))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }

                Spacer()

                Button(intent: TogglePlaybackIntent()) {
                    ZStack {
                        Circle().fill(accent).frame(width: 34, height: 34)
                        Image(systemName: entry.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.84))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                pbar(entry.progress / max(entry.duration, 1), accent: accent)
                HStack {
                    Text(entry.progress.mmss)
                    Spacer()
                    Text(entry.duration.mmss)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.52))
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            widgetBackground(entry, accent: accent)
        }
    }
}

struct MediumWidget: View {
    let entry: MusicEntry
    var accent: Color { Color(hex: entry.accentHex) ?? .pink }

    var body: some View {
        HStack(spacing: 14) {
            wArt(entry.imageData, size: 96, accent: accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(entry.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.62))
                    .lineLimit(1)
                Text(entry.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 18) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary.opacity(0.82))
                    }

                    Button(intent: TogglePlaybackIntent()) {
                        ZStack {
                            Circle().fill(accent).frame(width: 38, height: 38)
                            Image(systemName: entry.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }

                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary.opacity(0.82))
                    }
                }
                .buttonStyle(.plain)

                pbar(entry.progress / max(entry.duration, 1), accent: accent)
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            widgetBackground(entry, accent: accent)
        }
    }
}

struct LargeWidget: View {
    let entry: MusicEntry
    var accent: Color { Color(hex: entry.accentHex) ?? .pink }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                wArt(entry.imageData, size: 90, accent: accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(entry.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary.opacity(0.66))
                        .lineLimit(1)
                    if !entry.album.isEmpty {
                        Text(entry.album)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.42))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            pbar(entry.progress / max(entry.duration, 1), accent: accent)

            HStack {
                Text(entry.progress.mmss)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.52))
                Spacer()
                Text(entry.duration.mmss)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.52))
            }

            HStack {
                Spacer()
                HStack(spacing: 24) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.84))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }

                    Button(intent: TogglePlaybackIntent()) {
                        ZStack {
                            Circle().fill(accent).frame(width: 52, height: 52).shadow(color: accent.opacity(0.35), radius: 8)
                            Image(systemName: entry.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }

                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.84))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            widgetBackground(entry, accent: accent)
        }
    }
}

private func pbar(_ pct: Double, accent: Color) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.15)).frame(height: 4)
            Capsule().fill(accent).frame(width: max(0, geo.size.width * min(1, pct)), height: 4)
        }
    }
    .frame(height: 4)
}

@ViewBuilder
private func wArt(_ data: Data?, size: CGFloat, accent: Color) -> some View {
    if let d = data, let img = UIImage(data: d) {
        Image(uiImage: img).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
    } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [accent.opacity(0.8), Color.black.opacity(0.85)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay { Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundStyle(.secondary.opacity(0.8)) }
    }
}

@ViewBuilder
private func widgetBackground(_ entry: MusicEntry, accent: Color) -> some View {
    ZStack {
        if let d = entry.imageData, let img = UIImage(data: d) {

            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 40)
                .opacity(0.55)

            LinearGradient(
                colors: [.black.opacity(0.3), .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.12, blue: 0.16), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        LinearGradient(colors: [accent.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct MusicNowPlayingWidget: Widget {
    let kind = "SwingMusicNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MusicProvider()) { entry in
            MusicWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("See what's playing on Swing Music")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MusicWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MusicEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidget(entry: entry)
        case .systemMedium: MediumWidget(entry: entry)
        case .systemLarge: LargeWidget(entry: entry)
        default: MediumWidget(entry: entry)
        }
    }
}
