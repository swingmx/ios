import SwiftUI

struct PlayerOptionsSheet: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var sleepTimer = SleepTimer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    var showSleepTimer: Binding<Bool>
    var showEqualizer: Binding<Bool>
    var showPlaylistSheet: Binding<Bool>

    var body: some View {
        NavigationStack {
            List {
                if let t = player.current {
                    Section {
                        HStack(spacing: 14) {
                            AlbumArt(track: t, size: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                Text(t.artist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }

                    Section {
                        Button {
                            dismiss()
                            state.navigationTarget = .album(Album(stub: t.albumhash, title: t.album, image: t.image, date: t.date, albumartists: t.albumartists))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { state.showPlayer = false }
                        } label: {
                            Label("View Album", systemImage: "square.stack")
                        }

                        Button {
                            dismiss()
                            state.navigationTarget = .artist(Artist(stub: t.artisthash, name: t.artist, image: t.image))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { state.showPlayer = false }
                        } label: {
                            Label("View Artist", systemImage: "music.mic")
                        }

                        Button {
                            dismiss()
                            showPlaylistSheet.wrappedValue = true
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                    }

                    Section {
                        if downloadManager.isDownloaded(t) {
                            Button(role: .destructive) {
                                downloadManager.removeDownload(t)
                                dismiss()
                            } label: {
                                Label("Remove Download", systemImage: "trash")
                            }
                        } else {
                            Button {
                                downloadManager.download(t)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.blue)
                                    Text("Download")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    Section {
                        Toggle(isOn: $player.shuffle) {
                            HStack {
                                Image(systemName: "shuffle")
                                    .foregroundStyle(.blue)
                                Text("Shuffle")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .tint(.blue)

                        Picker(selection: Binding(
                            get: { player.audioQuality },
                            set: { player.audioQuality = $0 }
                        )) {
                            ForEach(AudioPlayer.AudioQuality.allCases, id: \.self) { q in
                                Text(q.label).tag(q)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.blue)
                                Text("Quality")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.blue)

                        Picker(selection: Binding(
                            get: { Int(player.crossfadeDuration) },
                            set: { player.crossfadeDuration = Double($0) }
                        )) {
                            Text("Off").tag(0)
                            Text("2s").tag(2)
                            Text("4s").tag(4)
                            Text("6s").tag(6)
                            Text("8s").tag(8)
                            Text("10s").tag(10)
                            Text("12s").tag(12)
                        } label: {
                            HStack {
                                Image(systemName: "wave.3.left.circle")
                                    .foregroundStyle(.blue)
                                Text("Crossfade")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.blue)

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showSleepTimer.wrappedValue = true }
                        } label: {
                            HStack {
                                Image(systemName: "moon.zzz")
                                    .foregroundStyle(.blue)
                                Text("Sleep Timer")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if sleepTimer.active {
                                    Text(sleepTimer.displayTime)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showEqualizer.wrappedValue = true }
                        } label: {
                            HStack {
                                Image(systemName: "slider.vertical.3")
                                    .foregroundStyle(.blue)
                                Text("Equalizer")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
