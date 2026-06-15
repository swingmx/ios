import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct MusicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicAttributes.self) { ctx in
            lockScreen(ctx)
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { ctx in
            let accent = accentFrom(ctx.state.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    albumThumb(ctx.state.imageData, size: 52, radius: 12)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ctx.state.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(ctx.state.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {

                        HStack(spacing: 28) {
                            Button(intent: PreviousTrackIntent()) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            Button(intent: TogglePlaybackIntent()) {
                                Image(systemName: ctx.state.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Button(intent: NextTrackIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 4) {
                            progressBar(ctx.state.progress / max(ctx.state.duration, 1), accent: accent)
                            HStack {
                                Text(ctx.state.progress.mmss)
                                Spacer()
                                Text("-" + max(0, ctx.state.duration - ctx.state.progress).mmss)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                albumThumb(ctx.state.imageData, size: 28, radius: 6)
            } compactTrailing: {
                HStack(spacing: 6) {
                    Image(systemName: ctx.state.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)

                    Circle()
                        .trim(from: 0, to: min(1, ctx.state.progress / max(ctx.state.duration, 1)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 12, height: 12)
                }
            } minimal: {
                ZStack {
                    Circle()
                        .trim(from: 0, to: min(1, ctx.state.progress / max(ctx.state.duration, 1)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    albumThumb(ctx.state.imageData, size: 18, radius: 5)
                }
                .frame(width: 22, height: 22)
            }
            .keylineTint(accent)
        }
    }

    private func lockScreen(_ ctx: ActivityViewContext<MusicAttributes>) -> some View {

        EmptyView()
            .frame(width: 0, height: 0)
            .opacity(0)
    }

    @ViewBuilder
    private func albumThumb(_ data: Data?, size: CGFloat, radius: CGFloat) -> some View {
        if let data, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.26, blue: 0.33), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8)).font(.system(size: size * 0.35)) }
        }
    }

    private func progressBar(_ pct: Double, accent: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: 3)
                Capsule().fill(accent).frame(width: max(0, geo.size.width * min(1, pct)), height: 3)
            }
        }
        .frame(height: 3)
    }

    private func accentFrom(_ hex: String) -> Color { Color(hex: hex) ?? .pink }
}
