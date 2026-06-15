import SwiftUI

struct AddToPlaylistSheet: View {
    let track: Track?
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newPlaylistName = ""
    @State private var showingCreateAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCreateAlert = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                            Text("New Playlist...")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.blue)

                            Spacer()
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                }

                Section {
                    if state.allPlaylists.isEmpty {
                        Text("No playlists yet")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 14))
                            .padding(.vertical, 20)
                    } else {
                        ForEach(state.allPlaylists) { pl in
                            Button {
                                if let t = track {
                                    Task {
                                        try? await API.shared.addTrackToPlaylist(pl.id, hash: t.trackhash)
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        dismiss()
                                    }
                                }
                            } label: {
                                AddToPlaylistRow(playlist: pl)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white.opacity(0.03))
                        }
                    }
                } header: {
                    if !state.allPlaylists.isEmpty { Text("Select Playlist") }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $showingCreateAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
                Button("Create") {
                    let name = newPlaylistName
                    newPlaylistName = ""
                    Task {
                        _ = try? await API.shared.createPlaylist(name)
                        await state.loadPlaylists()
                    }
                }
            } message: {
                Text("Enter a name for your new playlist.")
            }
        }
        .presentationDetents([.medium, .large])
        .task { await state.loadPlaylists() }
    }
}

struct AddToPlaylistRow: View {
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 16) {
            PlaylistImageGrid(playlist: playlist, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                Text("\(playlist.trackcount) songs").font(.system(size: 13, weight: .regular)).foregroundStyle(.white.opacity(0.3))
            }

            Spacer()
            Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(.white.opacity(0.15))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
