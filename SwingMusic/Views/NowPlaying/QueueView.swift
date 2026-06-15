import SwiftUI

struct QueueView: View {
    @ObservedObject var player = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    var backgroundImage: UIImage? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section(header: Text("Currently Playing")) {
                        QueueRow(track: current, active: true)
                    }
                }

                Section(header: Text("Next Up")) {
                    ForEach(player.queue.indices.filter { $0 > player.index }, id: \.self) { i in

                        HStack(spacing: editMode == .active ? 12 : 0) {
                            QueueRow(track: player.queue[i], active: false)

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    removeFromQueue(at: i)
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 38)
                                    .background(.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .frame(width: editMode == .active ? 52 : 0, alignment: .trailing)
                            .opacity(editMode == .active ? 1 : 0)
                            .clipped()
                            .disabled(editMode != .active)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: editMode)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { removeFromQueue(at: i) }
                            } label: {
                                Label("Remove", systemImage: "trash.fill")
                            }
                        }
                    }
                    .onMove(perform: move)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)

            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .fontWeight(editMode == .active ? .semibold : .regular)
                }
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
        }
    }

    private func removeFromQueue(at index: Int) {
        player.queue.remove(at: index)
    }

    private func move(from: IndexSet, to: Int) {
        let offset = player.index + 1
        player.queue.move(fromOffsets: from.map { $0 + offset }.asIndexSet(), toOffset: to + offset)
    }
}

private extension Array where Element == Int {
    func asIndexSet() -> IndexSet {
        var set = IndexSet()
        forEach { set.insert($0) }
        return set
    }
}

struct QueueRow: View {
    let track: Track
    let active: Bool
    @Environment(\.editMode) var editMode

    var body: some View {
        HStack(spacing: 12) {
            AlbumArt(track: track, size: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? .blue : .primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            if !active && editMode?.wrappedValue != .active {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
