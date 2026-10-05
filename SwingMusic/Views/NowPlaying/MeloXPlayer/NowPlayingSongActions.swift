import SwiftUI

struct NowPlayingSongActions: View {
    @Environment(AppState.self) private var state

    let song: Song
    var showsFavoriteButton = true

    @State private var isFavorite = false
    @State private var showSleepTimer = false
    @State private var showEqualizer = false
    @State private var showPlaylistSheet = false
    @ObservedObject private var sleepTimer = SleepTimer.shared

    var body: some View {
        HStack(spacing: 10) {
            if showsFavoriteButton {
                favoriteButton
            }

            songMenu
        }
        .task(id: song.trackhash) { await refreshFavorite() }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPlaylistSheet) {
            AddToPlaylistSheet(track: song)
                .environment(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var favoriteButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let newState = !isFavorite
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isFavorite = newState }
            Task {
                let confirmed = await state.setTrackFavorite(song, newState)
                if confirmed != newState {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isFavorite = confirmed }
                }
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title3.weight(.medium))
                .foregroundStyle(isFavorite ? Color.pink : .white)
                .symbolEffect(.bounce, value: isFavorite)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.13), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }

    private var songMenu: some View {
        Menu {
            Button {
                showPlaylistSheet = true
            } label: {
                Label("Add to Playlist…", systemImage: "music.note.list")
            }

            Button {
                state.navigationTarget = .album(
                    Album(
                        stub: song.albumhash,
                        title: song.album,
                        image: song.image,
                        date: song.date,
                        albumartists: song.albumartists
                    )
                )
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }

            if !song.artisthash.isEmpty {
                Button {
                    state.navigationTarget = .artist(
                        Artist(stub: song.artisthash, name: song.artist)
                    )
                } label: {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }

            Divider()

            Button {
                showSleepTimer = true
            } label: {
                Label(
                    sleepTimer.active ? "Sleep Timer · \(sleepTimer.displayTime)" : "Sleep Timer",
                    systemImage: "moon"
                )
            }

            Button {
                showEqualizer = true
            } label: {
                Label("Equalizer", systemImage: "slider.vertical.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.13), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    private func refreshFavorite() async {
        isFavorite = (try? await API.shared.checkFavorite(hash: song.trackhash, type: "track")) ?? false
    }
}
