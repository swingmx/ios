import SwiftUI

struct DownloadsView: View {
    @ObservedObject var dm = DownloadManager.shared
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if dm.downloadedTracks.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No Downloads")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Downloaded songs will appear here\nfor offline playback.")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {

                        HStack {
                            Text("\(dm.downloadedTracks.count) songs")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(dm.totalSize)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        ForEach(Array(dm.downloadedTracks.enumerated()), id: \.element.id) { i, track in
                            TrackRow(track: track, num: i + 1, active: state.player.current == track) {
                                state.player.play(track, from: dm.downloadedTracks)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    dm.removeDownload(track)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .background { AmbientBackground() }
        .navigationTitle("Downloads")
        .toolbar {
            if !dm.downloadedTracks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            state.player.playAll(dm.downloadedTracks)
                        } label: { Label("Play All", systemImage: "play.fill") }

                        Button {
                            state.player.playAll(dm.downloadedTracks, shuffled: true)
                        } label: { Label("Shuffle All", systemImage: "shuffle") }

                        Divider()

                        Button(role: .destructive) {
                            dm.removeAll()
                        } label: { Label("Remove All", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}
