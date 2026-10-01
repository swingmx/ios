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
    let progressAt: Date
    let duration: Double
    let imageData: Data?
    let accentHex: String

    var hasTrack: Bool { !title.isEmpty && title != "Not Playing" }

    var liveInterval: ClosedRange<Date>? {
        guard playing, duration > 0 else { return nil }
        let start = progressAt.addingTimeInterval(-progress)
        let end = start.addingTimeInterval(duration)
        return end > .now ? start...end : nil
    }

    var fraction: Double { duration > 0 ? min(1, max(0, progress / duration)) : 0 }

    static let preview = MusicEntry(
        date: .now, title: "Blue Plastic", artist: "Yung Lean", album: "Blue Plastic",
        playing: true, progress: 72, progressAt: .now, duration: 173,
        imageData: nil, accentHex: "#5E5CE6"
    )
}

struct MusicProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(context.isPreview ? .preview : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        let entry = read()
        let next = entry.liveInterval?.upperBound ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func read() -> MusicEntry {
        let d = UserDefaults(suiteName: "group.swingmusic")
        let at = d?.double(forKey: "w.progressAt") ?? 0
        return MusicEntry(
            date: .now,
            title: d?.string(forKey: "w.title") ?? "",
            artist: d?.string(forKey: "w.artist") ?? "",
            album: d?.string(forKey: "w.album") ?? "",
            playing: d?.bool(forKey: "w.playing") ?? false,
            progress: d?.double(forKey: "w.progress") ?? 0,
            progressAt: at > 0 ? Date(timeIntervalSince1970: at) : .now,
            duration: d?.double(forKey: "w.duration") ?? 0,
            imageData: d?.data(forKey: "w.image"),
            accentHex: d?.string(forKey: "w.accent") ?? "#5E5CE6"
        )
    }
}

private struct WidgetArtwork: View {
    let data: Data?
    let size: CGFloat
    var radius: CGFloat = 12

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let data, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .widgetAccentedRenderingMode(.accentedDesaturated)
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.fill.tertiary)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.34, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}

private struct WidgetProgress: View {
    let entry: MusicEntry
    var showsTimes = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let live = entry.liveInterval {
                    ProgressView(timerInterval: live, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: entry.fraction)
                }
            }
            .progressViewStyle(.linear)
            .tint(.white)
            .widgetAccentable()

            if showsTimes {
                HStack {
                    if let live = entry.liveInterval {
                        Text(timerInterval: live, countsDown: false)
                        Spacer()
                        HStack(spacing: 0) {
                            Text("-")
                            Text(timerInterval: live, countsDown: true)
                        }
                    } else {
                        Text(Self.mmss(entry.progress))
                        Spacer()
                        Text("-" + Self.mmss(max(0, entry.duration - entry.progress)))
                    }
                }
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    static func mmss(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

private struct ControlButton: View {
    let systemName: String
    let intent: any AppIntent
    var size: CGFloat
    var prominent = false

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)), in: .circle)
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }
}

private struct ControlsRow: View {
    let entry: MusicEntry
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.45) {
            ControlButton(systemName: "backward.fill", intent: PreviousTrackIntent(), size: size * 0.8)
            ControlButton(systemName: entry.playing ? "pause.fill" : "play.fill",
                          intent: TogglePlaybackIntent(), size: size, prominent: true)
            ControlButton(systemName: "forward.fill", intent: NextTrackIntent(), size: size * 0.8)
        }
    }
}

private struct TitleBlock: View {
    let entry: MusicEntry
    var titleFont: Font = .headline
    var subtitleFont: Font = .subheadline
    var lines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.hasTrack ? entry.title : "Not Playing")
                .font(titleFont)
                .foregroundStyle(.primary)
                .lineLimit(lines)
            Text(entry.hasTrack ? entry.artist : "Swing Music")
                .font(subtitleFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ArtworkBackdrop: View {
    let data: Data?

    var body: some View {
        Color.black
            .overlay {
                if let data, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                        .saturation(1.3)
                        .opacity(0.9)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
    }
}

struct SmallWidget: View {
    let entry: MusicEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetArtwork(data: entry.imageData, size: 64, radius: 10)
                Spacer(minLength: 0)
                ControlButton(systemName: entry.playing ? "pause.fill" : "play.fill",
                              intent: TogglePlaybackIntent(), size: 36, prominent: true)
            }
            Spacer(minLength: 6)
            TitleBlock(entry: entry, titleFont: .subheadline.weight(.semibold), subtitleFont: .caption)
            WidgetProgress(entry: entry)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { ArtworkBackdrop(data: entry.imageData) }
    }
}

struct MediumWidget: View {
    let entry: MusicEntry

    var body: some View {
        HStack(spacing: 14) {
            WidgetArtwork(data: entry.imageData, size: 124, radius: 14)
            VStack(alignment: .leading, spacing: 0) {
                TitleBlock(entry: entry, titleFont: .headline, subtitleFont: .subheadline, lines: 2)
                Spacer(minLength: 6)
                WidgetProgress(entry: entry)
                    .padding(.bottom, 10)
                ControlsRow(entry: entry, size: 38)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { ArtworkBackdrop(data: entry.imageData) }
    }
}

struct LargeWidget: View {
    let entry: MusicEntry

    var body: some View {
        GeometryReader { geo in
            let art = min(geo.size.width, geo.size.height - 150)
            VStack(alignment: .leading, spacing: 0) {
                WidgetArtwork(data: entry.imageData, size: art, radius: 16)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 10)
                TitleBlock(entry: entry, titleFont: .title3.weight(.semibold), subtitleFont: .body)
                WidgetProgress(entry: entry, showsTimes: true)
                    .padding(.top, 10)
                Spacer(minLength: 8)
                ControlsRow(entry: entry, size: 48)
                    .frame(maxWidth: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { ArtworkBackdrop(data: entry.imageData) }
    }
}

struct MusicNowPlayingWidget: Widget {
    let kind = "SwingMusicNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MusicProvider()) { entry in
            MusicWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Control what's playing in Swing Music.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MusicWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MusicEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidget(entry: entry)
        case .systemLarge: LargeWidget(entry: entry)
        default: MediumWidget(entry: entry)
        }
    }
}
