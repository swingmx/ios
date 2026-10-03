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
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if let n = num {
                        ZStack {
                            if active && !showArt {
                                NowPlayingIndicator(color: .accentColor)
                            } else {
                                Text("\(n)")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        .frame(minWidth: 26)
                    }

                    if showArt {
                        ZStack {
                            AlbumArt(track: track, size: 46)
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.45))
                                NowPlayingIndicator(color: .white)
                            }
                        }
                        .frame(width: 46, height: 46)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .explicitBadge(track.isExplicit)
                        HStack(spacing: 4) {
                            downloadIndicator
                            Text(track.allArtists)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(track.duration.mmss)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button { AudioPlayer.shared.addNext(track) } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Divider()
                Button { state.navigationTarget = .album(Album(stub: track.albumhash, title: track.album, image: track.image, date: track.date, albumartists: track.albumartists)) } label: { Label("View Album", systemImage: "square.stack") }
                if let artists = track.artists, artists.count > 1 {
                    Menu {
                        ForEach(artists, id: \.artisthash) { a in
                            Button(a.name) { state.navigationTarget = .artist(Artist(stub: a.artisthash, name: a.name, image: track.image)) }
                        }
                    } label: { Label("View Artist", systemImage: "music.mic") }
                } else {
                    Button { state.navigationTarget = .artist(Artist(stub: track.artisthash, name: track.artist, image: track.image)) } label: { Label("View Artist", systemImage: "music.mic") }
                }
                Button { state.requestedTrackForPlaylist = track } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
                let parent = (track.filepath as NSString).deletingLastPathComponent
                if !parent.isEmpty {
                    Button {
                        let name = (parent as NSString).lastPathComponent
                        state.navigationTarget = .folder(Folder(path: parent, name: name.isEmpty ? parent : name))
                    } label: { Label("Go to Folder", systemImage: "folder") }
                }
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
        .padding(.horizontal, 16).padding(.vertical, 8)
        .pullActions(
            leading: PullAction(label: "Add to queue", icon: "text.badge.plus", armedColor: .green) {
                AudioPlayer.shared.addLast(track)
            },
            trailing: favoritePullAction
        )
    }

    @EnvironmentObject var state: AppState

    private var favoritePullAction: PullAction {
        let isFavorite = state.isTrackFavorite(track)
        return PullAction(
            label: isFavorite ? "Remove" : "Add to favorites",
            icon: isFavorite ? "heart.slash.fill" : "heart.fill",
            armedColor: .red
        ) {
            Task { await state.setTrackFavorite(track, !isFavorite) }
        }
    }

    @ViewBuilder
    private var downloadIndicator: some View {
        switch downloadManager.downloads[track.trackhash] {
        case .queued:
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .downloading(let progress):
            DownloadRing(progress: progress)
                .frame(width: 10, height: 10)
                .animation(.linear(duration: 0.2), value: progress)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        default:
            if downloadManager.isDownloaded(track) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            }
        }
    }
}

// The playing track's marker: the system waveform, moving while audio plays and still when paused.
// Only the active row creates one, so only that row follows the player's state.
struct NowPlayingIndicator: View {
    var color: Color = .accentColor
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        Image(systemName: "waveform")
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: player.playing)
            .accessibilityLabel(player.playing ? "Now playing" : "Paused")
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
