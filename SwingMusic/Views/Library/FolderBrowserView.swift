import SwiftUI

struct FolderBrowserView: View {
    @EnvironmentObject var state: AppState
    var path: String = "$home"
    var title: String = "Folders"

    @State private var folders: [Folder] = []
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if loading {
                VStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .frame(minHeight: 400)
            } else if folders.isEmpty && tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 38)).foregroundStyle(.secondary)
                    Text("Empty folder").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                VStack(spacing: 0) {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            folderRow(folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { playFolder(folder, .play) } label: { Label("Play", systemImage: "play.fill") }
                            Button { playFolder(folder, .next) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { playFolder(folder, .queue) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
                        }
                        Divider().padding(.leading, 60)
                    }

                    if !tracks.isEmpty {
                        ForEach(tracks) { t in
                            TrackRow(track: t, active: state.player.current == t) {
                                state.player.play(t, from: tracks, source: .folder(path))
                            }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.top, 6)
            }
        }
        .background { AmbientBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Folder.self) { f in
            FolderBrowserView(path: f.path, title: f.name)
        }
        .task { await load() }
    }

    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(folderSubtitle(folder))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func folderSubtitle(_ folder: Folder) -> String {
        var parts: [String] = []
        if let f = folder.foldercount, f > 0 { parts.append("\(f) folder\(f == 1 ? "" : "s")") }
        if let t = folder.trackcount, t > 0 { parts.append("\(t) song\(t == 1 ? "" : "s")") }
        return parts.isEmpty ? "Folder" : parts.joined(separator: " · ")
    }

    private func load() async {
        let res = try? await API.shared.folder(path)
        folders = res?.folders ?? []
        tracks = res?.tracks ?? []
        loading = false
    }

    private enum FolderPlayMode { case play, next, queue }

    private func playFolder(_ folder: Folder, _ mode: FolderPlayMode) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            guard let all = try? await API.shared.folderTracks(folder.path), !all.isEmpty else { return }
            switch mode {
            case .play:
                state.player.playAll(all, source: .folder(folder.path))
            case .next:

                all.reversed().forEach { state.player.addNext($0) }
            case .queue:
                all.forEach { state.player.addLast($0) }
            }
        }
    }
}
