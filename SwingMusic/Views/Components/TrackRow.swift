import SwiftUI

struct TrackRow: View {
    let track: Track
    @ObservedObject var downloadManager = DownloadManager.shared
    var num: Int? = nil
    var active: Bool = false
    var showArt: Bool = true
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let n = num {
                ZStack {
                    if active {
                        Bars(color: .accentColor)
                    } else {
                        Text("\(n)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 26)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
            }

            if showArt {
                ZStack {
                    AlbumArt(track: track, size: 46)
                    if active {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.5))
                        Bars(color: .white).scaleEffect(0.7)
                    }
                }
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .foregroundStyle(.primary.opacity(active ? 1 : 0.9))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if downloadManager.isDownloaded(track) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Spacer()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            HStack(spacing: 16) {
                Text(track.duration.mmss)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .onTapGesture(perform: onTap)

                Menu {
                    Button { state.navigationTarget = .album(Album(albumhash: track.albumhash, title: track.album, image: track.image, date: track.date, duration: nil, trackcount: nil, albumartists: track.albumartists)) } label: { Label("View Album", systemImage: "square.stack") }
                    Button { state.navigationTarget = .artist(Artist(artisthash: track.artisthash, name: track.artist, image: track.image, trackcount: nil, albumcount: nil, duration: nil)) } label: { Label("View Artist", systemImage: "music.mic") }
                    Button { state.requestedTrackForPlaylist = track } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
                    Divider()
                    if DownloadManager.shared.isDownloaded(track) {
                        Button(role: .destructive) { DownloadManager.shared.removeDownload(track) } label: { Label("Remove Download", systemImage: "trash") }
                    } else {
                        Button { DownloadManager.shared.download(track) } label: { Label("Download", systemImage: "arrow.down.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(active ? .white.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onSwipeRight {
            AudioPlayer.shared.addLast(track)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    @EnvironmentObject var state: AppState
}

extension View {
    func onSwipeRight(action: @escaping () -> Void, label: String = "Queue", willFireLabel: String = "Added!", icon: String = "text.badge.plus", color: Color = .blue) -> some View {
        modifier(SwipeAction(action: action, label: label, willFireLabel: willFireLabel, icon: icon, color: color))
    }
}

struct Bars: View {
    var color: Color = .white
    @State private var go = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: go ? CGFloat.random(in: 4...14) : 3)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.08)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.06),
                        value: go
                    )
            }
        }
        .onAppear { go = true }
    }
}
