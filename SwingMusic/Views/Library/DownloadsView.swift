import SwiftUI

struct DownloadsView: View {
    @ObservedObject var dm = DownloadManager.shared
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if dm.downloadedTracks.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        infoBar

                        if !dm.downloadGroups.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(dm.downloadGroups) { group in
                                    NavigationLink(value: group) { groupRow(group) }
                                        .buttonStyle(.plain)
                                    if group.id != dm.downloadGroups.last?.id {
                                        Divider().padding(.leading, 60)
                                    }
                                }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
                            .padding(.horizontal, 16)
                        }

                        let singles = dm.ungroupedTracks
                        if !singles.isEmpty {
                            HStack {
                                Text("Tracks").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, dm.downloadGroups.isEmpty ? 4 : 26)
                            .padding(.bottom, 4)

                            ForEach(Array(singles.enumerated()), id: \.element.id) { i, track in
                                TrackRow(track: track, num: i + 1, active: state.player.current == track) {
                                    state.player.play(track, from: singles)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { dm.removeDownload(track) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
                .squeezeMiniPlayer(state)
            }
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground() }
        .navigationTitle("Downloads")
        .navigationDestination(for: DownloadManager.DownloadGroup.self) { DownloadedGroupView(group: $0) }
        .toolbar {
            if !dm.downloadedTracks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { state.player.playAll(dm.downloadedTracks) } label: { Label("Play All", systemImage: "play.fill") }
                        Button { state.player.playAll(dm.downloadedTracks, shuffled: true) } label: { Label("Shuffle All", systemImage: "shuffle") }
                        Divider()
                        Button(role: .destructive) { dm.removeAll() } label: { Label("Remove All", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var infoBar: some View {
        HStack {
            Text("\(dm.downloadedTracks.count) songs")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(dm.totalSize)
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func groupRow(_ group: DownloadManager.DownloadGroup) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if group.image.isEmpty {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon(group.kind)).font(.system(size: 18)).foregroundStyle(.blue)
                } else {
                    Img(url: API.shared.img(group.image, size: "small"), radius: 8)
                        .frame(width: 44, height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.system(size: 16)).foregroundStyle(.primary).lineLimit(1)
                Text("\(group.kind.rawValue.capitalized) · \(dm.tracks(in: group).count) songs")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func icon(_ kind: DownloadManager.DownloadGroup.Kind) -> String {
        switch kind {
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .folder: "folder.fill"
        case .mix: "square.stack.3d.up"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(.secondary.opacity(0.4))
            Text("No Downloads").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
            Text("Downloaded albums, playlists and songs\nwill appear here for offline playback.")
                .font(.system(size: 14)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DownloadedGroupView: View {
    let group: DownloadManager.DownloadGroup
    @ObservedObject var dm = DownloadManager.shared
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var tracks: [Track] { dm.tracks(in: group) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { state.player.playAll(tracks) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.primary, in: Capsule())
                    }
                    .buttonStyle(Pressed())
                    Button { state.player.playAll(tracks, shuffled: true) } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(Pressed())
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, num: i + 1, active: state.player.current == t) {
                        state.player.play(t, from: tracks)
                    }
                }
                Color.clear.frame(height: 100)
            }
        }
        .squeezeMiniPlayer(state)
        .background { AmbientBackground() }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    dm.removeGroup(group)
                    dismiss()
                } label: { Image(systemName: "trash") }
            }
        }
    }
}
