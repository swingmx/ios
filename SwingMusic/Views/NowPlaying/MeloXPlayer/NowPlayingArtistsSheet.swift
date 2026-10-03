import SwiftUI

// Opened by tapping the artist line in the player: every artist on the track, then its album,
// each opening its page. Mirrors the web client, where each artist name is its own link.
struct NowPlayingArtistsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let song: Song

    static func rowCount(for song: Song) -> Int { artists(of: song).count + 1 }

    // Track artists include featured ones; album artists are the fallback for tracks without them.
    static func artists(of song: Song) -> [TrackArtist] {
        var seen = Set<String>()
        let list = (song.artists?.isEmpty == false ? song.artists : song.albumartists) ?? []
        return list.filter { !$0.artisthash.isEmpty && seen.insert($0.artisthash).inserted }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.artists(of: song), id: \.artisthash) { artist in
                ArtistRow(artist: Artist(stub: artist.artisthash, name: artist.name,
                                         image: "\(artist.artisthash).webp")) { open(.artist($0)) }
            }
            AlbumRow(album: album) { open(.album($0)) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var album: Album {
        Album(stub: song.albumhash, title: song.album, image: song.image,
              date: song.date, albumartists: song.albumartists)
    }

    private func open(_ target: AppState.NavTarget) {
        dismiss()
        state.navigationTarget = target
    }
}

private struct ArtistRow: View {
    @EnvironmentObject private var state: AppState
    let artist: Artist
    let open: (Artist) -> Void
    @State private var isFavorite: Bool?

    var body: some View {
        SheetRow(title: artist.name, subtitle: "Artist", isFavorite: isFavorite,
                 open: { open(artist) },
                 toggle: { fav in await state.setArtistFavorite(artist, fav) }) {
            ArtistAvatar(artist: artist, size: 52)
        }
        .task(id: artist.artisthash) {
            isFavorite = try? await API.shared.checkFavorite(hash: artist.artisthash, type: "artist")
        }
    }
}

private struct AlbumRow: View {
    @EnvironmentObject private var state: AppState
    let album: Album
    let open: (Album) -> Void
    @State private var isFavorite: Bool?

    var body: some View {
        SheetRow(title: album.title, subtitle: "Album", isFavorite: isFavorite,
                 open: { open(album) },
                 toggle: { fav in await state.setAlbumFavorite(album, fav) }) {
            AlbumCover(album: album, size: 52)
        }
        .task(id: album.albumhash) {
            isFavorite = try? await API.shared.checkFavorite(hash: album.albumhash, type: "album")
        }
    }
}

private struct SheetRow<Artwork: View>: View {
    let title: String
    let subtitle: String
    let isFavorite: Bool?
    let open: () -> Void
    // Returns whether the server accepted the change.
    let toggle: (Bool) async -> Bool
    @ViewBuilder let artwork: Artwork

    @State private var shown: Bool?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    artwork.frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.semibold)).lineLimit(1)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if let fav = shown ?? isFavorite {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let new = !fav
                    withAnimation(.snappy) { shown = new }
                    Task {
                        if await !toggle(new) { withAnimation(.snappy) { shown = fav } }
                    }
                } label: {
                    Image(systemName: fav ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(fav ? Color.pink : .primary)
                        .symbolEffect(.bounce, value: fav)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(fav ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .padding(.vertical, 6)
    }
}
