import SwiftUI

struct AMLLDoc: Decodable {
    let type: String
    let Content: [Line]
    let SongWriters: [String]?
    let SyncedBy: String?
    let Provider: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case Content, SongWriters, SyncedBy, Provider
    }

    struct Syl: Decodable { let Text: String; let StartTime: Double; let EndTime: Double; let IsPartOfWord: Bool }
    struct Vocal: Decodable { let StartTime: Double; let EndTime: Double; let Syllables: [Syl] }
    struct Line: Decodable {
        let Lead: Vocal
        let Background: [Vocal]?
        let OppositeAligned: Bool?
    }
}

struct AMLLWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let start: Double
    let end: Double
    var dur: Double { max(0.08, end - start) }
    static func == (a: AMLLWord, b: AMLLWord) -> Bool { a.id == b.id }
}

struct AMLLLine: Identifiable, Equatable {
    let id = UUID()
    var words: [AMLLWord]
    var bg: [AMLLWord]
    var opposite: Bool
    var lineEnd: Double? = nil
    var start: Double { words.first?.start ?? 0 }
    var end: Double { lineEnd ?? Swift.max(words.last?.end ?? 0, bg.last?.end ?? 0) }
    static func == (a: AMLLLine, b: AMLLLine) -> Bool { a.id == b.id }
}

enum AMLLParser {
    private static func toWords(_ v: AMLLDoc.Vocal) -> [AMLLWord] {
        v.Syllables.map {
            AMLLWord(text: $0.Text + ($0.IsPartOfWord ? "" : " "),
                     start: $0.StartTime, end: max($0.EndTime, $0.StartTime))
        }
    }
    static func parse(_ doc: AMLLDoc) -> [AMLLLine] {
        doc.Content.compactMap { c in
            let words = toWords(c.Lead)
            guard !words.isEmpty else { return nil }
            let bg = (c.Background ?? []).flatMap(toWords)
            return AMLLLine(words: words, bg: bg, opposite: c.OppositeAligned ?? false)
        }
    }
}

@MainActor
private final class InAppResult {
    var data: Data?
    var done = false
}

@MainActor
final class AMLLEngine: ObservableObject {
    @Published var lines: [AMLLLine] = []
    @Published var writers: [String] = []
    @Published var syncedBy: String?
    @Published var provider: String?
    private var pendingCredits: (writers: [String], syncedBy: String?, provider: String?)?

    struct Credits: Decodable { let SongWriters: [String]?; let SyncedBy: String?; let Provider: String? }
    @Published var state: State = .idle
    enum State { case idle, loading, ready, empty }

    private var loadedID: String?
    private var loadTask: Task<Void, Never>?
    private var isFallback = false
    private var fallbackSignature = ""
    private static var cache: [String: (lines: [AMLLLine], writers: [String], syncedBy: String?, provider: String?)] = [:]

    static var lyricsServer: String { lyricsServers.first ?? "" }

    static var lyricsServers: [String] {
        var out: [String] = []
        if let s = UserDefaults.standard.string(forKey: "lyricsServer"), !s.isEmpty { out.append(s) }
        if let s = UserDefaults.standard.string(forKey: "server"),
           var c = URLComponents(string: s), let host = c.host, host != "localhost", host != "127.0.0.1" {
            c.port = 3000; c.path = ""; c.query = nil
            if let u = c.string { out.append(u) }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    func load(for track: Track) {
        if loadedID == track.id, state == .ready || state == .loading { return }
        loadTask?.cancel()
        loadedID = track.id
        isFallback = false

        if let hit = Self.cache[track.id] {
            lines = hit.lines; writers = hit.writers; syncedBy = hit.syncedBy; provider = hit.provider
            state = .ready
            return
        }
        state = .loading; lines = []; writers = []; syncedBy = nil; provider = nil; pendingCredits = nil

        let urls: [URL] = Self.lyricsServers.compactMap { base in
            guard var c = URLComponents(string: base) else { return nil }
            c.path = "/api/lyrics/for"
            c.queryItems = [
                URLQueryItem(name: "title", value: track.title),
                URLQueryItem(name: "artist", value: track.artist),
            ]
            return c.url
        }
        let id = track.id

        let info = LDDCLyrics.Track(title: track.title, artists: (track.artists ?? []).map(\.name),
                                    album: track.album, duration: track.duration)
        let inApp = InAppResult()
        let inAppTask = Task {
            inApp.data = await LDDCLyrics.shared.syllableDoc(for: info)
            inApp.done = true
            return inApp.data
        }

        loadTask = Task { [weak self] in
            var result: (Data, URLResponse)?
            for attempt in 0..<(urls.isEmpty ? 0 : urls.count + 1) {
                let url = urls[attempt % urls.count]
                var req = URLRequest(url: url)
                req.timeoutInterval = 6
                do {
                    result = try await URLSession.shared.data(for: req)
                    break
                } catch {
                    print("⚠️ Lyrics-Server nicht erreichbar (\(attempt + 1)): \(error.localizedDescription)")
                    if Task.isCancelled { return }
                    if inApp.done, inApp.data != nil { break }
                    if attempt % urls.count == urls.count - 1 { try? await Task.sleep(for: .seconds(2)) }
                }
            }
            guard let self, !Task.isCancelled, self.loadedID == id else { return }
            if let (d, r) = result, (r as? HTTPURLResponse)?.statusCode == 200,
               let c = try? JSONDecoder().decode(Credits.self, from: d) {
                self.pendingCredits = (c.SongWriters ?? [], c.SyncedBy, c.Provider)
            }
            var doc: AMLLDoc?
            if let (data, resp) = result, (resp as? HTTPURLResponse)?.statusCode == 200,
               let d = try? JSONDecoder().decode(AMLLDoc.self, from: data), d.type == "Syllable" {
                doc = d
            } else if let data = await inAppTask.value,
                      let d = try? JSONDecoder().decode(AMLLDoc.self, from: data) {
                doc = d
                print("🎤 AMLL: Wort-Lyrics aus der App (\(d.Provider ?? "?"))")
            }
            guard !Task.isCancelled, self.loadedID == id else { return }
            guard let doc else {
                if result == nil, !urls.isEmpty { self.loadedID = nil }
                self.state = .empty
                return
            }
            let parsed = AMLLParser.parse(doc)
            guard !parsed.isEmpty else { self.state = .empty; return }
            let writers = (doc.SongWriters ?? []).isEmpty ? (self.pendingCredits?.writers ?? []) : doc.SongWriters!
            Self.cache[id] = (parsed, writers, doc.SyncedBy, doc.Provider)
            self.lines = parsed
            self.writers = writers
            self.syncedBy = doc.SyncedBy
            self.provider = doc.Provider
            self.state = .ready
            print("🎤 AMLL: \(parsed.count) Zeilen geladen")
        }
    }

    func useFallback(_ parsed: ParsedLyrics?, trackID: String) {
        guard state == .empty || isFallback, loadedID == nil || loadedID == trackID,
              let parsed, parsed.synced, !parsed.lines.isEmpty else { return }
        let src = parsed.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let signature = trackID + "|" + src.map { "\($0.time)|\($0.text)" }.joined(separator: "\n")
        if isFallback, signature == fallbackSignature { return }
        var out: [AMLLLine] = []
        for (i, l) in src.enumerated() {
            let next = i + 1 < src.count ? src[i + 1].time : l.time + 6
            let end = max(l.time + 0.5, next)
            let words: [AMLLWord]
            if let ws = l.words, !ws.isEmpty {
                words = ws.enumerated().map { j, w in
                    let wEnd = j + 1 < ws.count ? ws[j + 1].time : end
                    return AMLLWord(text: w.text + (w.hasSpace ? " " : ""), start: w.time, end: max(w.time, wEnd))
                }
            } else {
                let parts = l.text.split(separator: " ", omittingEmptySubsequences: true)
                words = parts.map { AMLLWord(text: $0 + " ", start: l.time, end: l.time) }
            }
            var line = AMLLLine(words: words, bg: [], opposite: false)
            if let last = line.words.last, last.end < end {
                line.words[line.words.count - 1] = AMLLWord(text: last.text, start: last.start, end: last.start == last.end ? last.end : end)
            }
            line.lineEnd = end
            out.append(line)
        }
        guard !out.isEmpty else { return }
        isFallback = true
        fallbackSignature = signature
        lines = out
        writers = pendingCredits?.writers ?? []
        syncedBy = pendingCredits?.syncedBy
        provider = pendingCredits?.provider
        state = .ready
        print("🎤 AMLL: Zeilen-Lyrics der App als Ersatz (\(out.count) Zeilen)")
    }

    func activeIndex(at t: Double) -> Int {
        guard !lines.isEmpty else { return 0 }
        var idx = 0
        for (i, l) in lines.enumerated() where l.start <= t + 0.02 { idx = i }
        return idx
    }
}
