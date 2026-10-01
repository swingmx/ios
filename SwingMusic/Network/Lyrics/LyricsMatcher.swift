import Foundation

enum LyricsMatcher {
    static let minScore = 55.0
    static let maxDurationDelta = 4000

    struct Query: Sendable {
        let title: String
        let artists: [String]
        let album: String
        let durationMs: Int
    }

    static func score(_ q: Query, _ c: LyricsCandidate) -> Double? {
        if q.durationMs > 0, c.durationMs > 0, abs(q.durationMs - c.durationMs) > maxDurationDelta { return nil }
        let t = titleScore(q.title, c.title)
        let a: Double? = q.artists.isEmpty || c.artists.isEmpty ? nil : artistScore(q.artists, c.artists)
        let al: Double? = q.album.isEmpty || c.album.isEmpty
            ? nil : max(0, ratio(q.album.lowercased(), c.album.lowercased()) * 100)
        var s: Double
        switch (a, al) {
        case let (a?, al?): s = max(t * 0.5 + a * 0.5, t * 0.5 + a * 0.35 + al * 0.15)
        case let (a?, nil): s = t * 0.5 + a * 0.5
        case let (nil, al?): s = max(t * 0.7 + al * 0.3, t * 0.8)
        default: s = t
        }
        if t < 30 { s = max(0, s - 35) }
        return s > minScore ? s : nil
    }

    private static let symbolMap: [String: String] = [
        "（": "(", "）": ")", "：": ":", "！": "!", "？": "?", "／": "/", "＆": "&", "＊": "*",
        "＠": "@", "＃": "#", "＄": "$", "％": "%", "＼": "\\", "｜": "|", "＝": "=", "＋": "+",
        "－": "-", "＜": "<", "＞": ">", "［": "[", "］": "]", "｛": "{", "｝": "}",
        "【": "[", "】": "]", "’": "'", "‘": "'", "“": "\"", "”": "\"", "–": "-", "—": "-",
    ]

    static func unified(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (k, v) in symbolMap where t.contains(k) { t = t.replacingOccurrences(of: k, with: v) }
        return t.replacingOccurrences(of: #"\s"#, with: " ", options: .regularExpression)
    }

    static func ratio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        return 2 * Double(matchingCount(x, 0, x.count, y, 0, y.count)) / Double(x.count + y.count)
    }

    private static func matchingCount(_ a: [Character], _ alo: Int, _ ahi: Int,
                                      _ b: [Character], _ blo: Int, _ bhi: Int) -> Int {
        guard alo < ahi, blo < bhi else { return 0 }
        var bi = alo, bj = blo, best = 0
        var prev = [Int](repeating: 0, count: bhi - blo + 1)
        for i in alo..<ahi {
            var cur = [Int](repeating: 0, count: bhi - blo + 1)
            for j in blo..<bhi where a[i] == b[j] {
                let k = prev[j - blo] + 1
                cur[j - blo + 1] = k
                if k > best { best = k; bi = i - k + 1; bj = j - k + 1 }
            }
            prev = cur
        }
        guard best > 0 else { return 0 }
        return best
            + matchingCount(a, alo, bi, b, blo, bj)
            + matchingCount(a, bi + best, ahi, b, bj + best, bhi)
    }

    private static let tagRE = try! NSRegularExpression(
        pattern: #"\(([^()]*)\)|\[([^\[\]]*)\]|<([^<>]*)>|\s-\s(.+)$"#)

    private static let versionRE = try! NSRegularExpression(pattern:
        #"\b(live|remix(ed)?|mix(ed)?|edit(ed)?|inst\.?|instrumental|karaoke|off ?vocal|acoustic|version|ver\.?|"#
        + #"sped ?up|slowed|nightcore|demo|cover|tv ?size|extended|reverb|8d|piano|orchestral|unplugged|session|"#
        + #"a ?cappella|acapella)\b|伴奏|纯音乐|现场"#)
    private static let neutralRE = try! NSRegularExpression(pattern:
        #"^(feat\.?|ft\.?|featuring|with|from|prod\.?)\s|\b(remaster(ed)?|explicit|clean|deluxe|bonus|mono|stereo|"#
        + #"album version|single version|original version|original mix)\b|^\d{4}$"#)

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func splitTitle(_ title: String) -> (base: String, tags: [String]) {
        var tags: [String] = []
        let ns = NSRange(title.startIndex..., in: title)
        for m in tagRE.matches(in: title, range: ns) {
            for g in 1...4 {
                if let r = Range(m.range(at: g), in: title) {
                    tags.append(title[r].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        var base = tagRE.stringByReplacingMatches(in: title, range: ns, withTemplate: " ")
        base = base.replacingOccurrences(of: #"\s+(feat\.?|ft\.?)\s.*$"#, with: "", options: .regularExpression)
        base = base.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (base, tags.filter { !$0.isEmpty })
    }

    private static func isNeutral(_ tag: String) -> Bool { has(neutralRE, tag) }

    static func titleScore(_ t1: String, _ t2: String) -> Double {
        let a = unified(t1).lowercased(), b = unified(t2).lowercased()
        if a == b { return 100 }
        let score0 = max(0, ratio(a, b) * 100)

        let (base1, tags1) = splitTitle(a), (base2, tags2) = splitTitle(b)
        guard !base1.isEmpty, !base2.isEmpty else { return score0 }
        var rest1 = tags1.filter { !isNeutral($0) }
        var rest2 = tags2.filter { !isNeutral($0) }
        for t in rest1 where rest2.contains(t) {
            rest1.removeAll { $0 == t }
            rest2.removeAll { $0 == t }
        }
        let isVersion = { (t: String) in has(versionRE, t) }
        let v1 = rest1.filter(isVersion), v2 = rest2.filter(isVersion)
        let other1 = ([base1] + rest1.filter { !isVersion($0) }).joined(separator: " ")
        let other2 = ([base2] + rest2.filter { !isVersion($0) }).joined(separator: " ")
        let score1 = max(0, ratio(other1, other2) * 100)

        if v1.isEmpty, v2.isEmpty { return max(score1 * 0.7 + 30, score0) }
        var tagSim = 0.0
        if !v1.isEmpty, !v2.isEmpty {
            tagSim = v1.map { t in v2.map { ratio(t, $0) }.max() ?? 0 }.reduce(0, +) / Double(v1.count)
        }
        return max(score1 * 0.7 + tagSim * 30, min(score0, 69))
    }

    private static func splitArtists(_ list: [String]) -> [String] {
        list.flatMap { s -> [String] in
            unified(s).lowercased()
                .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring|x|vs\.?)\s+"#, with: "/", options: .regularExpression)
                .components(separatedBy: CharacterSet(charactersIn: ",、/\\&;・"))
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    private static func listScore(_ l1: [String], _ l2: [String]) -> Double {
        guard !l1.isEmpty, !l2.isEmpty else { return 0 }
        var pairs: [(Int, Int, Double)] = []
        for (i, a) in l1.enumerated() { for (j, b) in l2.enumerated() { pairs.append((i, j, ratio(a, b))) } }
        pairs.sort { $0.2 > $1.2 }
        var used1 = Set<Int>(), used2 = Set<Int>(), total = 0.0
        for (i, j, s) in pairs where !used1.contains(i) && !used2.contains(j) {
            used1.insert(i); used2.insert(j); total += s
            if used1.count == l1.count || used2.count == l2.count { break }
        }
        return total / Double(max(l1.count, l2.count))
    }

    static func artistScore(_ a1: [String], _ a2: [String]) -> Double {
        let l1 = splitArtists(a1), l2 = splitArtists(a2)
        guard !l1.isEmpty, !l2.isEmpty else { return 0 }
        var s = max(listScore(l1, l2), ratio(l1.joined(), l2.joined()))
        if l1[0] == l2[0] { s = max(s, 0.9) }
        return s * 100
    }
}
