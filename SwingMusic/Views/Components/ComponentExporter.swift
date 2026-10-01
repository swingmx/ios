#if DEBUG
import SwiftUI

@MainActor
enum ComponentExporter {
    static func runIfRequested(state: AppState) {
        if UserDefaults.standard.bool(forKey: "captureLandscape") {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
            }
        }
        guard UserDefaults.standard.bool(forKey: "exportComponents") else { return }
        UserDefaults.standard.set(false, forKey: "exportComponents")
        Task { await exportAll(state: state) }
    }

    private struct Item: Encodable { let name: String; let file: String; let w: Int; let h: Int }

    static func exportAll(state: AppState) async {
        var albums = (try? await API.shared.recentlyAdded(12)) ?? []
        var artists = (try? await API.shared.artists(limit: 6))?.items ?? []
        var tracks: [Track] = albums.first != nil
            ? ((try? await API.shared.albumTracks(albums.first!.albumhash)) ?? [])
            : []

        if albums.isEmpty { albums = [Self.sampleAlbum] }
        if artists.isEmpty { artists = [Self.sampleArtist] }
        if tracks.isEmpty { tracks = [Self.sampleTrack] }

        let album = albums.first

        let sizes = ["", "small", "medium", "large"]
        var urls: [URL] = []
        for a in albums.prefix(4) { for s in sizes { if let u = API.shared.img(a.image, size: s) { urls.append(u) } } }
        for t in tracks.prefix(4) { for s in sizes { if let u = API.shared.img(t.image, size: s) { urls.append(u) } } }
        for ar in artists.prefix(3) { for s in sizes { if let u = API.shared.artistImg(ar.image, size: s) { urls.append(u) } } }
        await preload(urls)

        for url in urls where Img.cache[url.absoluteString] == nil {
            let seed = abs(url.deletingLastPathComponent().lastPathComponent.hashValue)
            Img.cache[url.absoluteString] = gradientCover(seed: seed)
        }

        var renders: [(String, AnyView)] = []

        if let album {
            renders.append(("AlbumCard", AnyView(AlbumCard(album: album, size: 150))))
            renders.append(("AlbumCover", AnyView(AlbumCover(album: album, size: 220))))
        }
        if let artist = artists.first {
            renders.append(("ArtistCard", AnyView(ArtistCard(artist: artist, size: 110))))
            renders.append(("Avatar", AnyView(ArtistAvatar(artist: artist, size: 160))))
        }
        if let t = tracks.first {
            renders.append(("TrackRow", AnyView(ExportTrackRow(track: t, num: 1).frame(width: 390))))
            renders.append(("ChartRow", AnyView(ExportChartRow(track: t, rank: 1).frame(width: 390))))
        }
        if let album {
            renders.append(("HeroCard", AnyView(ExportHeroCard(album: album))))
        }
        renders.append(("Buttons", AnyView(ExportButtons())))
        renders.append(("SectionHeader", AnyView(ExportSectionHeader())))
        renders.append(("TabBar", AnyView(ExportTabBar())))

        let dir = docsDir().appendingPathComponent("components", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var manifest: [Item] = []
        for (name, view) in renders {
            let darkView = view.environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: darkView.fixedSize())
            renderer.scale = 3
            renderer.isOpaque = false
            guard let ui = renderer.uiImage, let data = ui.pngData() else {
                print("⚠️ export failed: \(name)"); continue
            }
            let file = "\(name).png"
            try? data.write(to: dir.appendingPathComponent(file))
            manifest.append(Item(name: name, file: file, w: Int(ui.size.width * ui.scale), h: Int(ui.size.height * ui.scale)))
            print("✅ exported \(name)  \(Int(ui.size.width))×\(Int(ui.size.height))pt")
        }

        if let mdata = try? JSONEncoder().encode(manifest) {
            try? mdata.write(to: dir.appendingPathComponent("manifest.json"))
        }
        print("📦 Components exported to: \(dir.path)")
    }

    private static func preload(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls where Img.cache[url.absoluteString] == nil {
                group.addTask {
                    var req = URLRequest(url: url)
                    if let t = API.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
                    if let (data, _) = try? await Net.session.data(for: req),
                       let ui = UIImage(data: data) {
                        await MainActor.run { Img.cache[url.absoluteString] = ui }
                    }
                }
            }
        }
    }

    private static func docsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func gradientCover(seed: Int) -> UIImage {
        let palettes: [[UIColor]] = [
            [UIColor(red:0.36,green:0.24,blue:0.42,alpha:1), UIColor(red:0.06,green:0.06,blue:0.10,alpha:1)],
            [UIColor(red:0.13,green:0.30,blue:0.42,alpha:1), UIColor(red:0.05,green:0.07,blue:0.10,alpha:1)],
            [UIColor(red:0.42,green:0.18,blue:0.22,alpha:1), UIColor(red:0.08,green:0.05,blue:0.07,alpha:1)],
            [UIColor(red:0.18,green:0.34,blue:0.28,alpha:1), UIColor(red:0.05,green:0.08,blue:0.07,alpha:1)],
        ]
        let cols = palettes[seed % palettes.count]
        let size = CGSize(width: 600, height: 600)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            let cg = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [cols[0].cgColor, cols[1].cgColor] as CFArray,
                                  locations: [0, 1])!
            cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let note = "♪" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 200, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            let sz = note.size(withAttributes: attrs)
            note.draw(at: CGPoint(x: (size.width - sz.width)/2, y: (size.height - sz.height)/2), withAttributes: attrs)
        }
    }

    static var sampleAlbum: Album {
        decode(#"{"albumhash":"sample","title":"Midnight Tapes","image":"sample.jpg","date":1704067200,"duration":2890,"trackcount":12,"albumartists":[{"name":"Aurora Lane","artisthash":"a1"}]}"#)
    }
    static var sampleArtist: Artist {
        decode(#"{"artisthash":"a1","name":"Aurora Lane","image":"sample.jpg","trackcount":84,"albumcount":6,"duration":21340}"#)
    }
    static var sampleTrack: Track {
        decode(#"{"trackhash":"t1","title":"Neon Skyline","album":"Midnight Tapes","albumhash":"sample","duration":204,"filepath":"/x.mp3","image":"sample.jpg","trackno":1,"disc":1,"date":1704067200,"bitrate":320,"artists":[{"name":"Aurora Lane","artisthash":"a1"}],"albumartists":[{"name":"Aurora Lane","artisthash":"a1"}],"artisthashes":["a1"]}"#)
    }
}

private struct ExportButtons: View {
    var body: some View {
        HStack(spacing: 12) {
            Label("Play", systemImage: "play.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 150, height: 46).background(.white, in: Capsule())
            Label("Shuffle", systemImage: "shuffle")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 150, height: 46)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
        .padding(8)
    }
}

private struct ExportSectionHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Recently Played").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(8)
    }
}

private struct ExportTrackRow: View {
    let track: Track
    let num: Int
    var body: some View {
        HStack(spacing: 12) {
            Text("\(num)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5)).frame(width: 26)
            AlbumArt(track: track, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(track.duration.mmss).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(width: 390)
    }
}

private struct ExportChartRow: View {
    let track: Track
    let rank: Int
    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)").font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.accentColor).frame(width: 30)
            AlbumArt(track: track, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(width: 390)
    }
}

private struct ExportHeroCard: View {
    let album: Album
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Img(url: API.shared.img(album.image, size: ""), radius: 0)
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.45), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("FORGOTTEN FAVORITE").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65)).kerning(0.8)
                Text(album.title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                Text(album.artist).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            .padding(18).padding(.trailing, 70)
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(18)
        }
        .frame(width: 330, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ExportTabBar: View {
    var body: some View {
        HStack(spacing: 14) {
            tab("Listening Now", icon: "house.fill", active: true)
            tab("Library", icon: "music.note.list", active: false)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(8)
    }
    private func tab(_ label: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 18))
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(active ? Color.accentColor : .white.opacity(0.6))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(active ? AnyShapeStyle(.white.opacity(0.1)) : AnyShapeStyle(.clear), in: Capsule())
    }
}
#endif

#if DEBUG
import SwiftUI

@MainActor
enum DebugCapture {
    static func runIfRequested(state: AppState) {
        guard let route = UserDefaults.standard.string(forKey: "captureRoute"), !route.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "captureRoute")
        UserDefaults.standard.synchronize()
        Task { await go(route: route, state: state) }
    }

    private static func go(route: String, state: AppState) async {
        if state.recentAdded.isEmpty { await state.loadHome() }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let albums = (try? await API.shared.recentlyAdded(40)) ?? []
        let album = albums.first { !$0.image.isEmpty } ?? albums.first

        switch route {
        case "home":
            state.showPlayer = false
        case "artist":
            if let name = UserDefaults.standard.string(forKey: "captureArtist"),
               let a = (try? await API.shared.search(name))?.artists?.first {
                state.homePath.append(a)
                break
            }
            let artists = (try? await API.shared.artists(limit: 60))?.items ?? []
            if let a = artists.first(where: { !$0.image.isEmpty && ($0.trackcount ?? 0) > 0 }) ?? artists.first {
                state.homePath.append(a)
            }
        case "album":
            if let name = UserDefaults.standard.string(forKey: "captureAlbum"),
               let a = (try? await API.shared.search(name))?.albums?.first {
                state.homePath.append(a)
                break
            }
            if let album { state.homePath.append(album) }
        case "lyrics":
            let q = UserDefaults.standard.string(forKey: "captureSong") ?? "Boylife"
            let hits = (try? await API.shared.search(q))?.tracks ?? []
            if let t = hits.first(where: { $0.title.localizedCaseInsensitiveContains(q) }) ?? hits.first {
                state.player.play(t, from: hits)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                state.player.seek(UserDefaults.standard.double(forKey: "captureSeek"))
            }
            NowPlayingView.debugStartPage = .lyrics
            try? await Task.sleep(nanoseconds: 800_000_000)
            state.showPlayer = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NotificationCenter.default.post(name: .init("debugOpenLyrics"), object: nil)
        case "queue":
            let hits = (try? await API.shared.search("a"))?.tracks ?? []
            if let first = hits.first {
                state.player.play(first, from: hits)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                state.player.next()
                try? await Task.sleep(nanoseconds: 800_000_000)
                state.player.next()
            }
            NowPlayingView.debugStartPage = .queue
            try? await Task.sleep(nanoseconds: 800_000_000)
            state.showPlayer = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NotificationCenter.default.post(name: .init("debugOpenQueue"), object: nil)
        case "widgets":
            NotificationCenter.default.post(name: .init("debugShowWidgets"), object: nil)
        case "eq":
            NotificationCenter.default.post(name: .init("debugShowEqualizer"), object: nil)
        case "player" where UserDefaults.standard.string(forKey: "capturePlayerSong") != nil:
            let q = UserDefaults.standard.string(forKey: "capturePlayerSong") ?? ""
            let hits = (try? await API.shared.search(q))?.tracks ?? []
            if let t = hits.first(where: { $0.title.localizedCaseInsensitiveContains(q) }) ?? hits.first {
                state.player.play(t, from: hits)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                state.player.seek(UserDefaults.standard.double(forKey: "capturePlayerSeek"))
            }
            NowPlayingView.debugStartPage = .artwork
            try? await Task.sleep(nanoseconds: 800_000_000)
            state.showPlayer = true
        case "player", "miniplay":
            var tracks: [Track] = []
            if let album { tracks = (try? await API.shared.albumTracks(album.albumhash)) ?? [] }
            if tracks.isEmpty { tracks = state.topTracks }
            if let first = tracks.first {
                state.player.play(first, from: tracks)
            }
            if route == "player" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                state.showPlayer = true
            }
        default:
            break
        }
    }
}
#endif
