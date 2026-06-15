import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var player = AudioPlayer.shared
    @Binding var expanded: Bool

    private var compact: Bool { state.keyboardVisible || (state.scrollingDown && state.scrollOffset < -40) }

    var body: some View {
        if player.current != nil {
            Group {
                if #available(iOS 26.0, *) {
                    content
                        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                } else {
                    content
                        .background(.regularMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.24), lineWidth: 0.6)
                        )
                }
            }
            .contentShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .frame(maxWidth: compact ? 180 : .infinity)
            .padding(.horizontal, compact ? 0 : 20)
            .padding(.bottom, 58)
            .animation(.smooth(duration: 0.3), value: compact)
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if !expanded { expanded = true }
                }
            )
        }
    }

    private var progress: CGFloat {
        guard player.total > 0 else { return 0 }
        return CGFloat(min(max(player.time / player.total, 0), 1))
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: compact ? 6 : 10) {
                if let t = player.current {
                    AlbumArt(track: t, size: compact ? 26 : 36)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))

                    if !compact {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(t.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            player.toggle()
                        }
                    } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: compact ? 13 : 16))
                            .foregroundStyle(.primary)
                            .frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
                    }
                    .buttonStyle(.plain)

                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: compact ? 10 : 13))
                            .foregroundStyle(.secondary)
                            .frame(width: compact ? 20 : 28, height: compact ? 24 : 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, compact ? 8 : 14)
            .padding(.vertical, compact ? 5 : 8)

            if !compact {
                GeometryReader { geo in
                    Capsule()
                        .fill(.white)
                        .frame(width: max(4, geo.size.width * progress), height: 2)
                        .animation(.linear(duration: 0.3), value: progress)
                }
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }
}
