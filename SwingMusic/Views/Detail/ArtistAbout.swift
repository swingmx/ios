import SwiftUI

struct WikipediaSummary: Equatable {
    let extract: String
    let url: URL
    let language: String
}

@MainActor
enum WikipediaService {
    private static var cache: [String: WikipediaSummary?] = [:]

    private static let musicWords = [
        "musik", "sänger", "rapper", "band", "produzent", "dj", "songwriter", "komponist", "gruppe", "duo",
        "music", "singer", "musician", "producer", "group", "composer",
    ]

    static func summary(for artist: String, hint: String?) async -> WikipediaSummary? {
        let key = artist.lowercased()
        if let hit = cache[key] { return hit }
        var result: WikipediaSummary?
        search: for lang in ["de", "en"] {
            for query in [hint.map { "\(artist) \($0)" }, artist].compactMap({ $0 }) {
                if let s = await lookup(artist, query: query, lang: lang) { result = s; break search }
            }
        }
        cache[key] = result
        return result
    }

    private static func fetch(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.setValue("SwingMusicClient/1.0 (iOS; personal music app)", forHTTPHeaderField: "User-Agent")
        return try? await URLSession.shared.data(for: req).0
    }

    private static func lookup(_ artist: String, query: String, lang: String) async -> WikipediaSummary? {
        var c = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"),
            .init(name: "srsearch", value: query), .init(name: "srlimit", value: "5"),
            .init(name: "format", value: "json"),
        ]
        struct Search: Decodable {
            struct Q: Decodable { let search: [Hit] }
            struct Hit: Decodable { let title: String }
            let query: Q
        }
        guard let url = c.url,
              let data = await fetch(url),
              let hits = try? JSONDecoder().decode(Search.self, from: data).query.search
        else { return nil }

        let name = artist.lowercased()
        for hit in hits where hit.title.lowercased().contains(name) || name.contains(hit.title.lowercased()) {
            let title = hit.title.replacingOccurrences(of: " ", with: "_")
            guard let enc = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let sURL = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(enc)")
            else { continue }
            struct Summary: Decodable {
                let type: String
                let description: String?
                let extract: String
                struct Urls: Decodable { struct D: Decodable { let page: String }; let desktop: D }
                let content_urls: Urls
            }
            guard let sd = await fetch(sURL),
                  let s = try? JSONDecoder().decode(Summary.self, from: sd),
                  s.type == "standard", !s.extract.isEmpty
            else { continue }
            let text = ((s.description ?? "") + " " + s.extract.prefix(300)).lowercased()
            guard musicWords.contains(where: { text.contains($0) }),
                  let page = URL(string: s.content_urls.desktop.page)
            else { continue }
            return WikipediaSummary(extract: s.extract, url: page, language: lang)
        }
        return nil
    }
}

struct ArtistAboutSection: View {
    let artistName: String
    var hint: String?
    @State private var summary: WikipediaSummary?
    @State private var expanded = false

    var body: some View {
        Group {
            if let summary {
                VStack(alignment: .leading, spacing: 12) {
                    Text("About \(artistName)")
                        .font(.title2.bold())
                        .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(summary.extract)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(expanded ? nil : 4)
                            .animation(.smooth(duration: 0.3), value: expanded)
                        HStack {
                            Button(expanded ? "Less" : "More") {
                                withAnimation(.smooth(duration: 0.3)) { expanded.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Link(destination: summary.url) {
                                Label("Wikipedia", systemImage: "arrow.up.right")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DetailCardFill.color, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 18)
                }
                .transition(.opacity)
            }
        }
        .task(id: artistName) {
            let s = await WikipediaService.summary(for: artistName, hint: hint)
            withAnimation(.smooth(duration: 0.3)) { summary = s }
        }
    }
}
