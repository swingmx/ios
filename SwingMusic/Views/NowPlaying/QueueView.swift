import SwiftUI

struct QueueView: View {
    @ObservedObject var player = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    var backgroundImage: UIImage? = nil

    private var previousIndices: [Int] {
        player.queue.indices.filter { $0 < player.index }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {

                if !previousIndices.isEmpty {
                    Section(header: Text("Previously Played")) {
                        ForEach(previousIndices, id: \.self) { i in
                            QueueRow(track: player.queue[i], active: false)
                                .contentShape(Rectangle())
                                .onTapGesture { player.play(player.queue[i], from: player.queue) }
                        }
                    }
                }

                if let current = player.current {
                    Section(header: Text("Currently Playing")) {
                        QueueRow(track: current, active: true)
                            .id("current")
                    }
                }

                Section(header: Text("Next Up")) {
                    ForEach(player.queue.indices.filter { $0 > player.index }, id: \.self) { i in
                        QueueRow(track: player.queue[i], active: false)
                            .contentShape(Rectangle())
                            .onTapGesture { player.jump(to: i) }

                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation(AudioPlayer.queueAnim) { removeFromQueue(at: i) }
                                } label: {
                                    Label("Remove", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)

            .environment(\.colorScheme, .dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {

                if !previousIndices.isEmpty {
                    DispatchQueue.main.async {
                        proxy.scrollTo("current", anchor: .top)
                    }
                }
            }
            }
        }
    }

    private func removeFromQueue(at index: Int) {
        player.queue.remove(at: index)
    }
}

struct QueueRow: View {
    let track: Track
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            AlbumArt(track: track, size: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? .blue : .primary)
                    .lineLimit(1)
                Text(track.allArtists)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
