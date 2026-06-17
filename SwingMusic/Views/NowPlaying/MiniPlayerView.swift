import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var player = AudioPlayer.shared
    @Binding var expanded: Bool

    private var compact: Bool { state.scrollingDown && state.scrollOffset < -60 }

    var body: some View {
        if player.current != nil && !state.keyboardVisible {
            Group {
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular, in: Capsule(style: .continuous))
                } else {
                    content
                        .background(.regularMaterial, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.24), lineWidth: 0.6))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .frame(maxWidth: compact ? 188 : .infinity, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)
            .padding(.bottom, 58)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: compact)
        }
    }

    private var progress: CGFloat {
        guard player.total > 0 else { return 0 }
        return CGFloat(min(max(player.time / player.total, 0), 1))
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let t = player.current {

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        expanded = true
                    } label: {
                        HStack(spacing: 10) {
                            AlbumArt(track: t, size: compact ? 30 : 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                                Spacer(minLength: 0)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { player.toggle() }
                    } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !compact {
                        Button { player.next() } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, 7)

            if !compact {
                GeometryReader { geo in
                    Capsule()
                        .fill(.white.opacity(0.9))
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

@available(iOS 26.0, *)
struct NowPlayingAccessory: View {
    @Binding var expanded: Bool
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @State private var current: Track?
    @State private var playing = false

    private let player = AudioPlayer.shared
    private var inline: Bool { placement == .inline }

    var body: some View {
        Group {
            if let t = current {
                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        expanded = true
                    } label: {
                        HStack(spacing: 10) {
                            AlbumArt(track: t, size: inline ? 24 : 32)
                                .clipShape(RoundedRectangle(cornerRadius: inline ? 5 : 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !inline {
                                    Text(t.artist)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !inline {
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .onReceive(player.$current) { current = $0 }
        .onReceive(player.$playing) { playing = $0 }
    }
}
