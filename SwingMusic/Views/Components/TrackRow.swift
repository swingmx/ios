import SwiftUI

// The screen a list of tracks is shown on, so a track's menu doesn't offer to go where you already are.
enum TrackListContext: Equatable {
    case none
    case album(String)
    case artist(String)
    case folder(String)
}

private struct TrackListContextKey: EnvironmentKey {
    static let defaultValue: TrackListContext = .none
}

extension EnvironmentValues {
    var trackListContext: TrackListContext {
        get { self[TrackListContextKey.self] }
        set { self[TrackListContextKey.self] = newValue }
    }
}

// What a track's menu offers, given the screen it is on.
enum TrackMenuRules {
    enum ArtistEntry: Equatable {
        case hidden
        case single(TrackArtist)
        // Every artist on the track; `current` is the one whose screen this is, shown but inactive.
        case list([TrackArtist], current: String?)
    }

    static func showsViewAlbum(_ track: Track, in context: TrackListContext) -> Bool {
        context != .album(track.albumhash)
    }

    static func folder(of track: Track) -> String {
        (track.filepath as NSString).deletingLastPathComponent
    }

    static func showsGoToFolder(_ track: Track, in context: TrackListContext) -> Bool {
        let parent = folder(of: track)
        guard !parent.isEmpty else { return false }
        if case .folder(let path) = context { return trimmed(path) != trimmed(parent) }
        return true
    }

    static func artistEntry(_ track: Track, in context: TrackListContext) -> ArtistEntry {
        var artists = track.artists ?? []
        if artists.isEmpty { artists = [TrackArtist(name: track.artist, artisthash: track.artisthash)] }
        if case .artist(let hash) = context, artists.contains(where: { $0.artisthash == hash }) {
            return artists.count == 1 ? .hidden : .list(artists, current: hash)
        }
        return artists.count == 1 ? .single(artists[0]) : .list(artists, current: nil)
    }

    // Server folder paths may end with a slash; a track's folder doesn't.
    private static func trimmed(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

struct TrackRow: View {
    let track: Track
    @ObservedObject var downloadManager = DownloadManager.shared
    var num: Int? = nil
    var active: Bool = false
    var showArt: Bool = true
    var onTap: () -> Void

    // Sizes at the default text size, scaled with the user's text size setting. The .body and
    // .subheadline styles also scale but start a point larger, which made rows feel oversized.
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if let n = num {
                        ZStack {
                            if active && !showArt {
                                NowPlayingIndicator(color: .appAccent)
                            } else {
                                Text("\(n)")
                                    .font(.system(size: numberSize, weight: .medium).monospacedDigit())
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
                            .font(.system(size: titleSize))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .explicitBadge(track.isExplicit)
                        HStack(spacing: 4) {
                            downloadIndicator
                            Text(track.allArtists)
                                .font(.system(size: detailSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                TrackMenuItems(track: track)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            // rows low on screen open upward, and iOS would list the items bottom to top
            .menuOrder(.fixed)
        }
        .padding(.horizontal, DetailLayout.inset).padding(.vertical, 8)
        .pullActions(
            leading: PullAction(label: "Add to queue", icon: "text.badge.plus", armedColor: .green) {
                AudioPlayer.shared.addLast(track)
            },
            trailing: favoritePullAction
        )
    }

    @Environment(AppState.self) var state

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

// A track's menu, shared by track rows, search results and the now playing screen.
struct TrackMenuItems: View {
    let track: Track
    var showsPlayNext = true
    // the now playing screen shows its own playlist sheet; elsewhere the app's one opens
    var onAddToPlaylist: (() -> Void)? = nil
    @Environment(\.trackListContext) private var listContext
    @Environment(AppState.self) private var state

    var body: some View {
        if showsPlayNext {
            Button { AudioPlayer.shared.addNext(track) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Divider()
        }
        if TrackMenuRules.showsViewAlbum(track, in: listContext) {
            Button { state.navigationTarget = .album(Album(stub: track.albumhash, title: track.album, image: track.image, date: track.date, albumartists: track.albumartists)) } label: { Label("View Album", systemImage: "square.stack") }
        }
        switch TrackMenuRules.artistEntry(track, in: listContext) {
        case .hidden:
            EmptyView()
        case .single(let a):
            Button { viewArtist(a) } label: { Label("View Artist", systemImage: "music.mic") }
        case .list(let artists, let current):
            Menu {
                ForEach(artists, id: \.artisthash) { a in
                    Button(a.name) { viewArtist(a) }
                        .disabled(a.artisthash == current)
                }
            } label: { Label("View Artist", systemImage: "music.mic") }
        }
        Button {
            if let onAddToPlaylist { onAddToPlaylist() } else { state.requestedTrackForPlaylist = track }
        } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
        if TrackMenuRules.showsGoToFolder(track, in: listContext) {
            let parent = TrackMenuRules.folder(of: track)
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
    }

    private func viewArtist(_ a: TrackArtist) {
        state.navigationTarget = .artist(Artist(stub: a.artisthash, name: a.name))
    }
}

// The playing track's marker: the system waveform, moving while audio plays and still when paused.
// Only the active row creates one, so only that row follows the player's state.
struct NowPlayingIndicator: View {
    var color: Color = .accentColor
    @State private var playing = AudioPlayer.shared.playing
    @Environment(AppState.self) private var state

    var body: some View {
        Image(systemName: "waveform")
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            // Covered by the full player it still redraws every frame, so it rests while the player is open.
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: playing && !state.showPlayer)
            .accessibilityLabel(playing ? "Now playing" : "Paused")
            .onReceive(AudioPlayer.shared.$playing.removeDuplicates()) { playing = $0 }
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
