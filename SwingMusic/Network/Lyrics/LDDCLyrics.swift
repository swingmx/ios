import CryptoKit
import Foundation

actor LDDCLyrics {
    static let shared = LDDCLyrics()

    private let providers: [any LyricsProvider] = [QQMusicProvider(), KugouProvider(), NetEaseProvider()]
    private var inflight: [String: Task<Data?, Never>] = [:]

    struct Track: Sendable {
        let title: String
        let artists: [String]
        let album: String
        let duration: Int
    }

    func syllableDoc(for t: Track) async -> Data? {
        let key = Self.cacheKey(t)
        switch Self.readCache(key) {
        case .hit(let d): return d
        case .miss: return nil
        case .none: break
        }
        if let running = inflight[key] { return await running.value }
        let task = Task { await self.resolve(t) }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    private struct Found: Sendable {
        let candidate: LyricsCandidate
        let score: Double
        let lines: [TimedLine]
        let verbatim: Bool
    }

    private enum Outcome: Sendable { case found(Found), none, failed }

    private func resolve(_ t: Track) async -> Data? {
        let q = LyricsMatcher.Query(title: t.title, artists: t.artists, album: t.album, durationMs: t.duration * 1000)
        let artistTitle = "\(t.artists.first ?? "") - \(t.title)"

        let outcomes: [Outcome] = await withTaskGroup(of: Outcome.self) { group in
            for p in providers {
                group.addTask { await Self.fetch(from: p, q: q, keywords: [artistTitle, t.title]) }
            }
            var out: [Outcome] = []
            for await o in group { out.append(o) }
            return out
        }
        let found = outcomes.compactMap { if case .found(let f) = $0 { f } else { nil } }
        let key = Self.cacheKey(t)
        guard let best = Self.pick(found) else {
            print("🔎 LDDC: nichts Wort-genaues für „\(t.title)“")
            let failed = outcomes.contains { if case .failed = $0 { true } else { false } }
            if !failed, !Task.isCancelled { Self.writeMiss(key) }
            return nil
        }
        print("🔎 LDDC: \(best.candidate.source.displayName) — „\(best.candidate.title)“ von \(best.candidate.artists.joined(separator: ", ")) (\(Int(best.score)) Punkte)")
        let doc = LDDCPostProcess.syllableJSON(best.lines, artists: t.artists,
                                               provider: best.candidate.source.displayName)
        if let doc { Self.writeCache(key, doc) } else { Self.writeMiss(key) }
        return doc
    }

    private static func fetch(from p: any LyricsProvider, q: LyricsMatcher.Query, keywords: [String]) async -> Outcome {
        for keyword in keywords {
            let results: [LyricsCandidate]
            do { results = try await p.search(keyword) } catch {
                print("⚠️ LDDC \(p.source.displayName): Suche fehlgeschlagen (\(error.localizedDescription))")
                return .failed
            }
            let ranked = results
                .compactMap { c in LyricsMatcher.score(q, c).map { (c, $0) } }
                .sorted { $0.1 > $1.1 }
            guard !ranked.isEmpty else { continue }
            var failed = false
            for (c, score) in ranked.prefix(3) {
                guard !Task.isCancelled else { return .failed }
                do {
                    guard let lines = try await p.lyrics(for: c), plausible(lines, q.durationMs) else { continue }
                    return .found(Found(candidate: c, score: score, lines: lines, verbatim: LyricsFormats.isVerbatim(lines)))
                } catch {
                    failed = true
                }
            }
            return failed ? .failed : .none
        }
        return .none
    }

    private static func plausible(_ lines: [TimedLine], _ durationMs: Int) -> Bool {
        let starts = lines.flatMap { $0.words.map(\.start) }
        guard let last = starts.max(), !starts.isEmpty else { return false }
        return durationMs <= 0 || last <= durationMs + 5000
    }

    private static func pick(_ found: [Found]) -> Found? {
        guard let top = found.map(\.score).max() else { return nil }
        let close = found.filter { top - $0.score <= 15 && $0.verbatim }
        return LyricsSource.allCases.lazy.compactMap { s in close.first { $0.candidate.source == s } }.first
    }

    private enum CacheResult { case hit(Data), miss }
    private static let missTTL: TimeInterval = 3 * 24 * 3600

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lddc-lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func cacheKey(_ t: Track) -> String {
        let raw = "v1|\(t.title.lowercased())|\(t.artists.first?.lowercased() ?? "")|\(t.duration)"
        return SHA256.hash(data: Data(raw.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func readCache(_ key: String) -> CacheResult? {
        let hit = dir.appendingPathComponent(key + ".json")
        if let d = try? Data(contentsOf: hit) { return .hit(d) }
        let miss = dir.appendingPathComponent(key + ".none")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: miss.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < missTTL {
            return .miss
        }
        return nil
    }

    private static func writeCache(_ key: String, _ data: Data) {
        try? data.write(to: dir.appendingPathComponent(key + ".json"), options: .atomic)
    }

    private static func writeMiss(_ key: String) {
        try? Data().write(to: dir.appendingPathComponent(key + ".none"), options: .atomic)
    }
}

enum LDDCPostProcess {
    private static let creditRE = try! NSRegularExpression(pattern:
        #"作词|作曲|编曲|制作|混音|监制|著作权|翻译作品|享有本|词\s*[:：]|曲\s*[:：]"#
        + #"|Producer|Produced by|Written|Composed|Lyrics by|Music by|Arranged"#
        + #"|Recorded|Recording|Mixed by|Mastered|Vocals recorded|Engineered"#
        + #"|All Rights Reserved|Used by Permission|administered|Publishing"#
        + #"|©|℗|:／|："#, options: [.caseInsensitive])
    private static let writerRE = try! NSRegularExpression(pattern:
        #"(?:作词|作曲|作詞|词|曲|Written by|Composed by|Lyrics by|Music by|Songwriter)s?\s*[:：]?\s*(.+)"#,
        options: [.caseInsensitive])
    private static let nameJunkRE = try! NSRegularExpression(pattern:
        #"著作权|翻译|Publishing|administered|Rights Reserved|Permission|Inc\.|LLC|BMI|ASCAP|©|℗|\d{4}"#,
        options: [.caseInsensitive])

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func writers(_ lines: [TimedLine]) -> [String] {
        var names: [String] = []
        for l in lines {
            let text = l.text.trimmingCharacters(in: .whitespaces)
            guard let m = writerRE.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text) else { continue }
            let parts = String(text[r])
                .replacingOccurrences(of: #" x | X "#, with: "/", options: .regularExpression)
                .components(separatedBy: CharacterSet(charactersIn: "/／、,&"))
            for p in parts {
                let n = p.trimmingCharacters(in: CharacterSet(charactersIn: " :：-/／"))
                if n.count > 1, n.count < 40, !has(nameJunkRE, n), !names.contains(n) { names.append(n) }
            }
        }
        return Array(names.prefix(8))
    }

    private struct Tok { var text: String; var start: Int; var end: Int }

    private static func tokens(_ line: TimedLine) -> [Tok] {
        var out: [Tok] = []
        for w in line.words {
            if w.text.trimmingCharacters(in: .whitespaces).isEmpty {
                if !out.isEmpty, !out[out.count - 1].text.hasSuffix(" ") { out[out.count - 1].text += " " }
                continue
            }
            out.append(Tok(text: w.text, start: w.start, end: w.end))
        }
        return out
    }

    private static func splitBackground(_ words: [Tok]) -> (lead: [Tok], bg: [Tok]) {
        var lead: [Tok] = [], bg: [Tok] = [], depth = 0
        for w in words {
            let inBG = depth > 0 || w.text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
            depth = max(0, depth + w.text.filter { $0 == "(" }.count - w.text.filter { $0 == ")" }.count)
            if inBG { bg.append(w) } else { lead.append(w) }
        }
        return lead.isEmpty ? (words, []) : (lead, bg)
    }

    private static func syllables(_ words: [Tok]) -> [[String: Any]] {
        words.enumerated().map { i, w in
            let next = i + 1 < words.count ? words[i + 1].start : nil
            var end = max(w.end, w.start)
            if let next, next > end, next - end < 120 { end = next }
            let text = w.text.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .trimmingCharacters(in: .whitespaces)
            return [
                "Text": text,
                "StartTime": Double(w.start) / 1000,
                "EndTime": Double(end) / 1000,
                "IsPartOfWord": next != nil && !w.text.hasSuffix(" "),
            ]
        }
    }

    static func syllableJSON(_ lines: [TimedLine], artists: [String], provider: String) -> Data? {
        var content: [[String: Any]] = []
        var started = false
        let artistL = artists.map { $0.lowercased() }.filter { !$0.isEmpty }

        for line in lines {
            let toks = tokens(line).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !toks.isEmpty else { continue }
            let raw = line.text
            let lower = raw.lowercased()
            let isCredit = has(creditRE, raw)
            let looksLikeHeader = raw.contains(" - ")
                || artistL.contains { lower.contains($0) }
                || (raw.contains("(") && raw.contains(")") && raw.count < 40)
            if isCredit || (!started && looksLikeHeader) { continue }
            started = true

            let (lead, bg) = splitBackground(toks)
            let leadSyl = syllables(lead)
            guard let first = leadSyl.first, let last = leadSyl.last else { continue }
            var entry: [String: Any] = [
                "Lead": ["StartTime": first["StartTime"]!, "EndTime": last["EndTime"]!, "Syllables": leadSyl],
                "OppositeAligned": false,
            ]
            let bgSyl = syllables(bg)
            if let bf = bgSyl.first, let bl = bgSyl.last {
                entry["Background"] = [["StartTime": bf["StartTime"]!, "EndTime": bl["EndTime"]!, "Syllables": bgSyl]]
            }
            content.append(entry)
        }
        guard content.count >= 3 else { return nil }

        var doc: [String: Any] = ["Type": "Syllable", "Content": content, "Provider": provider, "_source": "lddc-app"]
        let w = writers(lines)
        if !w.isEmpty { doc["SongWriters"] = w }
        return try? JSONSerialization.data(withJSONObject: doc)
    }
}
