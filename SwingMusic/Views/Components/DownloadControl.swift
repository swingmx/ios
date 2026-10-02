import SwiftUI

struct DownloadControl: View {
    let tracks: [Track]
    var size: CGFloat = 46
    var group: DownloadManager.DownloadGroup? = nil
    @ObservedObject private var dm = DownloadManager.shared

    private var total: Int { tracks.count }

    private var completedCount: Int {
        tracks.filter { dm.downloads[$0.trackhash] == .completed }.count
    }

    private var activeProgress: Double {
        tracks.reduce(0.0) { acc, t in
            if case .downloading(let p) = dm.downloads[t.trackhash] { return acc + p }
            return acc
        }
    }

    private var isActive: Bool {
        tracks.contains { t in
            switch dm.downloads[t.trackhash] {
            case .downloading, .queued: return true
            default: return false
            }
        }
    }

    private var allDone: Bool { total > 0 && completedCount == total }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completedCount) + activeProgress) / Double(total))
    }

    var body: some View {
        Button(action: tap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                if allDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if isActive {
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.22)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: size * 0.18, height: size * 0.18)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: allDone)
        }
        .buttonStyle(Pressed())
        .accessibilityLabel(allDone ? "Downloaded" : isActive ? "Downloading" : "Download")
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allDone {
            if let group { dm.removeGroup(group) } else { for t in tracks { dm.removeDownload(t) } }
        } else if isActive {
            return
        } else {
            dm.downloadAll(tracks, group: group)
        }
    }
}

struct DownloadRing: View {
    let progress: Double
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

// The ⋯ toolbar menu on album, playlist, mix and artist screens.
// `queueTracks` supplies what Play Next / Add to Queue use, for screens whose full list is fetched on demand.
// A nil `group` shows Download disabled.
struct CollectionActionsMenu: View {
    let tracks: [Track]
    var group: DownloadManager.DownloadGroup?
    var queueTracks: (() async -> [Track])?
    @ObservedObject private var dm = DownloadManager.shared
    @Environment(\.displayScale) private var displayScale

    private var allDownloaded: Bool {
        !tracks.isEmpty && tracks.allSatisfy { dm.downloads[$0.trackhash] == .completed }
    }

    private var isDownloading: Bool {
        tracks.contains { t in
            switch dm.downloads[t.trackhash] {
            case .downloading, .queued: true
            default: false
            }
        }
    }

    private var progress: Double {
        guard !tracks.isEmpty else { return 0 }
        let done = tracks.reduce(0.0) { acc, t in
            switch dm.downloads[t.trackhash] {
            case .completed: acc + 1
            case .downloading(let p): acc + p
            default: acc
            }
        }
        return min(1, done / Double(tracks.count))
    }

    // Menu items only take images, so the ring is rendered to one; it reflects progress when the menu opens.
    private var progressIcon: Image {
        let renderer = ImageRenderer(content: DownloadRing(progress: progress, lineWidth: 2.5).frame(width: 22, height: 22))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return Image(systemName: "arrow.down.circle.dotted") }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    private func enqueue(_ add: @escaping @MainActor ([Track]) -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            add(await queueTracks?() ?? tracks)
        }
    }

    var body: some View {
        Menu {
            Button { enqueue { AudioPlayer.shared.addNext($0) } } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { enqueue { AudioPlayer.shared.addLast($0) } } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            Divider()
            if let group {
                if allDownloaded {
                    Button(role: .destructive) { dm.removeGroup(group) } label: { Label("Remove Download", systemImage: "trash") }
                } else if isDownloading {
                    Button {} label: {
                        Label { Text("Downloading \(Int(progress * 100))%") } icon: { progressIcon }
                    }
                } else {
                    Button { dm.downloadAll(tracks, group: group) } label: { Label("Download", systemImage: "arrow.down.circle") }
                }
            } else {
                Button {} label: { Label("Download", systemImage: "arrow.down.circle") }
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More actions")
    }
}
