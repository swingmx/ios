import Foundation

struct TimedWord: Sendable {
    var start: Int
    var end: Int
    var text: String
}

struct TimedLine: Sendable {
    var start: Int
    var end: Int
    var words: [TimedWord]
    var text: String { words.map(\.text).joined() }
}

enum LyricsFormats {
    static func isVerbatim(_ lines: [TimedLine]) -> Bool {
        let filled = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard filled.count >= 3 else { return false }
        let words = filled.reduce(0) { $0 + $1.words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count }
        return Double(words) / Double(filled.count) >= 1.5
    }

    private static let qrcContent = try! NSRegularExpression(
        pattern: #"<Lyric_1 LyricType="1" LyricContent="(.*?)"/>"#, options: [.dotMatchesLineSeparators])
    private static let lineRE = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    private static let qrcWordRE = try! NSRegularExpression(
        pattern: #"(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)*)\((\d+),(\d+)\)"#)
    private static let qrcOnlyStamp = try! NSRegularExpression(pattern: #"^\(\d+,\d+\)$"#)

    static func parseQQ(_ text: String) -> [TimedLine] {
        if let m = qrcContent.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text) {
            return parseQRC(unescapeXML(String(text[r])))
        }
        return parseLRC(text)
    }

    static func parseQRC(_ content: String) -> [TimedLine] {
        var out: [TimedLine] = []
        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let (start, end, body) = lineHead(line) else { continue }
            if body.hasPrefix("("), body.hasSuffix(")"), matches(qrcOnlyStamp, body) {
                out.append(TimedLine(start: start, end: end, words: []))
                continue
            }
            var words: [TimedWord] = []
            for m in qrcWordRE.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                let text = group(m, 1, body)
                guard text != "\r", let s = Int(group(m, 2, body)), let d = Int(group(m, 3, body)) else { continue }
                words.append(TimedWord(start: s, end: s + d, text: text))
            }
            if words.isEmpty { words = [TimedWord(start: start, end: end, text: body)] }
            out.append(TimedLine(start: start, end: end, words: words))
        }
        return out
    }

    private static let krcWordRE = try! NSRegularExpression(
        pattern: #"(?:\[\d+,\d+\])?<(\d+),(\d+),\d+>((?:.(?!\d+,\d+,\d+>))*)"#)

    static func parseKRC(_ krc: String) -> [TimedLine] {
        var out: [TimedLine] = []
        for raw in krc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let (start, end, body) = lineHead(line) else { continue }
            var words: [TimedWord] = []
            for m in krcWordRE.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let o = Int(group(m, 1, body)), let d = Int(group(m, 2, body)) else { continue }
                words.append(TimedWord(start: start + o, end: start + o + d, text: group(m, 3, body)))
            }
            if words.isEmpty { words = [TimedWord(start: start, end: end, text: body)] }
            out.append(TimedLine(start: start, end: end, words: words))
        }
        return out
    }

    private static let yrcWordRE = try! NSRegularExpression(
        pattern: #"(?:\[\d+,\d+\])?\((\d+),(\d+),\d+\)((?:.(?!\d+,\d+,\d+\)))*)"#)

    static func parseYRC(_ yrc: String) -> [TimedLine] {
        var out: [TimedLine] = []
        for raw in yrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let (start, end, body) = lineHead(line) else { continue }
            var words: [TimedWord] = []
            for m in yrcWordRE.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let s = Int(group(m, 1, body)), let d = Int(group(m, 2, body)) else { continue }
                words.append(TimedWord(start: s, end: s + d, text: group(m, 3, body)))
            }
            if words.isEmpty { words = [TimedWord(start: start, end: end, text: body)] }
            out.append(TimedLine(start: start, end: end, words: words))
        }
        return out
    }

    private static let lrcStamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+)(?:[.:](\d+))?\]"#)

    static func parseLRC(_ lrc: String) -> [TimedLine] {
        var stamped: [(Int, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = NSRange(raw.startIndex..., in: raw)
            let ms = lrcStamp.matches(in: raw, range: ns)
            guard let last = ms.last, let r = Range(last.range, in: raw) else { continue }
            let text = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            for m in ms {
                let mm = Int(group(m, 1, raw)) ?? 0, ss = Int(group(m, 2, raw)) ?? 0
                let fracStr = group(m, 3, raw)
                var frac = Int(fracStr) ?? 0
                if fracStr.count == 1 { frac *= 100 } else if fracStr.count == 2 { frac *= 10 }
                stamped.append(((mm * 60 + ss) * 1000 + frac, text))
            }
        }
        stamped.sort { $0.0 < $1.0 }
        return stamped.enumerated().map { i, e in
            let end = i + 1 < stamped.count ? stamped[i + 1].0 : e.0 + 5000
            return TimedLine(start: e.0, end: end, words: [TimedWord(start: e.0, end: end, text: e.1)])
        }
    }

    private static func lineHead(_ line: String) -> (Int, Int, String)? {
        guard let m = lineRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let s = Int(group(m, 1, line)), let d = Int(group(m, 2, line)) else { return nil }
        return (s, s + d, group(m, 3, line))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        guard let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func unescapeXML(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
