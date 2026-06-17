import SwiftUI

struct DownloadControl: View {
    let tracks: [Track]
    var size: CGFloat = 46
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
        .accessibilityLabel(allDone ? "Heruntergeladen" : isActive ? "Lädt herunter" : "Herunterladen")
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allDone {
            for t in tracks { dm.removeDownload(t) }
        } else if isActive {
            return
        } else {
            dm.downloadAll(tracks)
        }
    }
}
