import Foundation

struct ServerLyricLine: Codable {
    let text: String
    let time: Double
}

enum LyricsContent: Codable {
    case string(String)
    case lines([ServerLyricLine])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let l = try? container.decode([ServerLyricLine].self) {
            self = .lines(l)
        } else {

            self = .string("")
        }
    }
}

struct LyricsResponse: Codable {
    let lyrics: LyricsContent?
    let synced: Bool?
    let copyright: String?
}

struct LyricWord: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String
    var hasSpace: Bool = true
}

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
    var words: [LyricWord]? = nil
}

struct ParsedLyrics {
    let lines: [LyricLine]
    let synced: Bool
    let copyright: String?
}

struct LRCLibResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

func parseLyrics(_ response: LyricsResponse, trackDuration: Int? = nil, wordByWordForUnsynced: Bool = false) -> ParsedLyrics {
    guard let content = response.lyrics else {
        print("💡 Parse: Rohdaten sind nil.")
        return ParsedLyrics(lines: [], synced: false, copyright: nil)
    }

    switch content {
    case .lines(let serverLines):
        print("💡 Parse: Server-JSON-Lines erkannt (\(serverLines.count) Zeilen).")
        let isMs = serverLines.contains { $0.time > 1000 } && (trackDuration ?? 0) < 3600
        if let first = serverLines.first, let last = serverLines.last {
            print("💡 Parse-Debug: Line 1 Text: '\(first.text)', Last Line Text: '\(last.text)'")
        }

        let combinedRegex = try? NSRegularExpression(pattern: #"(?:<|\[)(\d{1,2}):(\d{2})(?:[\.:,](\d{1,3}))?(?:>|\])"#)

        let lines = serverLines.map { sl -> LyricLine in
            let lineTime = isMs ? sl.time / 1000.0 : sl.time
            var rawText = sl.text

            var lineWords: [LyricWord]? = nil
            let nsText = rawText as NSString

            if let combinedRegex = combinedRegex {
                let matches = combinedRegex.matches(in: rawText, range: NSRange(location: 0, length: nsText.length))
                if !matches.isEmpty {
                    var components: [(time: Double, text: String, space: Bool)] = []
                    var lastPos = 0

                    for (idx, m) in matches.enumerated() {
                        let currentTextRange = NSRange(location: lastPos, length: m.range.location - lastPos)
                        let rawChunk = nsText.substring(with: currentTextRange)
                        let hasSpace = rawChunk.hasSuffix(" ")
                        let currentText = rawChunk.trimmingCharacters(in: .whitespaces)

                        if idx == 0 && !currentText.isEmpty {
                            components.append((time: lineTime, text: currentText, space: hasSpace))
                        }

                        let wMin = Double(nsText.substring(with: m.range(at: 1))) ?? 0
                        let wSec = Double(nsText.substring(with: m.range(at: 2))) ?? 0
                        var wFrac = 0.0
                        if m.range(at: 3).location != NSNotFound {
                            let wpt = nsText.substring(with: m.range(at: 3))
                            if wpt.count == 3 { wFrac = (Double(wpt) ?? 0) / 1000 }
                            else if wpt.count == 2 { wFrac = (Double(wpt) ?? 0) / 100 }
                            else if wpt.count == 1 { wFrac = (Double(wpt) ?? 0) / 10 }
                        }
                        let currentTime = wMin * 60 + wSec + wFrac

                        let nextPos = m.range.location + m.range.length
                        let endOfText = (idx + 1 < matches.count) ? matches[idx+1].range.location : nsText.length
                        let nextTextRange = NSRange(location: nextPos, length: endOfText - nextPos)
                        let rawNext = nsText.substring(with: nextTextRange)
                        let nextHasSpace = rawNext.hasSuffix(" ")
                        let nextText = rawNext.trimmingCharacters(in: .whitespaces)

                        components.append((time: currentTime, text: nextText, space: nextHasSpace))
                        lastPos = endOfText
                    }
                    if !components.isEmpty {
                        lineWords = components.map { LyricWord(time: $0.time, text: $0.text, hasSpace: $0.space) }
                    }
                }
            }

            let cleanText = rawText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                .replacingOccurrences(of: #"\[\d{1,2}:\d{2}(?:[\.:,]\d{1,3})?\]"#, with: "", options: .regularExpression, range: nil)
                .trimmingCharacters(in: .whitespaces)

            return LyricLine(time: lineTime, text: cleanText, words: lineWords)
        }
        return ParsedLyrics(lines: lines, synced: response.synced ?? true, copyright: response.copyright)

    case .string(let raw):
        guard !raw.isEmpty else {
            print("💡 Parse: Rohdaten-String ist leer.")
            return ParsedLyrics(lines: [], synced: false, copyright: nil)
        }
        print("💡 Parse: Verarbeite \(raw.count) Zeichen an Lyrics-Daten (Synced: \(response.synced ?? false)).")
        let synced = response.synced ?? false
        guard synced else {
            let rows = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            print("💡 Parse: Unsynced Lyrics erkannt (\(rows.count) Zeilen). Spacing wird berechnet...")

            let total = Double(trackDuration ?? (rows.count * 5))
            let step = rows.count > 0 ? total / Double(rows.count) : 0

            let lines = rows.enumerated().map { LyricLine(time: Double($0.offset) * step, text: $0.element) }
            return ParsedLyrics(lines: lines, synced: false, copyright: response.copyright)
        }
        let res = parseLRC(response)
        if res.lines.isEmpty {

            return parseLyrics(LyricsResponse(lyrics: content, synced: false, copyright: response.copyright), trackDuration: trackDuration)
        }
        return res
    }
}

func parseLRC(_ response: LyricsResponse) -> ParsedLyrics {
    guard let content = response.lyrics, case .string(let raw) = content, !raw.isEmpty else {
        return ParsedLyrics(lines: [], synced: false, copyright: nil)
    }
    let synced = response.synced ?? false
    guard synced else {
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { LyricLine(time: Double($0.offset), text: $0.element) }
        return ParsedLyrics(lines: lines, synced: false, copyright: response.copyright)
    }
    var lines: [LyricLine] = []

    let linePattern = #"\[(\d{1,2}):(\d{2})(?:[\.:,](\d{1,3}))?\]"#
    guard let timestampRegex = try? NSRegularExpression(pattern: linePattern) else {
        return ParsedLyrics(lines: [], synced: false, copyright: nil)
    }

    let wordPattern = "<(\\d{1,2}):(\\d{2})(?:[\\.:,](\\d{1,3}))?>([^<]+)"
    let wordRegex = try? NSRegularExpression(pattern: wordPattern)

    for row in raw.components(separatedBy: "\n") {
        let nsRow = row as NSString
        let matches = timestampRegex.matches(in: row, range: NSRange(location: 0, length: nsRow.length))
        guard let firstMatch = matches.first else { continue }

        let min = Double(nsRow.substring(with: firstMatch.range(at: 1))) ?? 0
        let sec = Double(nsRow.substring(with: firstMatch.range(at: 2))) ?? 0
        var frac = 0.0
        if firstMatch.range(at: 3).location != NSNotFound {
            let part = nsRow.substring(with: firstMatch.range(at: 3))
            if part.count == 3 { frac = (Double(part) ?? 0) / 1000 }
            else if part.count == 2 { frac = (Double(part) ?? 0) / 100 }
            else if part.count == 1 { frac = (Double(part) ?? 0) / 10 }
        }
        let lineTime = min * 60 + sec + frac

        let textStart = firstMatch.range.location + firstMatch.range.length
        let rawText = nsRow.substring(from: textStart).trimmingCharacters(in: .whitespaces)
        guard !rawText.isEmpty else { continue }

        var lineWords: [LyricWord]? = nil
        let activeWordRegex = wordRegex
        let altWordRegex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[\.:,](\d{1,3}))?\]"#)

        var extracted: [LyricWord] = []
        let nsText = rawText as NSString

        var components: [(time: Double, text: String, space: Bool)] = []

        let combinedRegex = try? NSRegularExpression(pattern: #"(?:<|\[)(\d{1,2}):(\d{2})(?:[\.:,](\d{1,3}))?(?:>|\])"#)
        if let combinedRegex = combinedRegex {
            let matches = combinedRegex.matches(in: rawText, range: NSRange(location: 0, length: nsText.length))

            var lastPos = 0
            for (idx, m) in matches.enumerated() {

                let currentTextRange = NSRange(location: lastPos, length: m.range.location - lastPos)
                let rawChunk = nsText.substring(with: currentTextRange)
                let hasSpace = rawChunk.hasSuffix(" ") || rawChunk.hasSuffix("\t") || rawChunk.hasSuffix("\u{00A0}")
                let currentText = rawChunk.trimmingCharacters(in: .whitespaces)

                if idx == 0 {
                    if !currentText.isEmpty {
                        components.append((time: lineTime, text: currentText, space: hasSpace))
                    }
                } else if !currentText.isEmpty {

                }

                let wMin = Double(nsText.substring(with: m.range(at: 1))) ?? 0
                let wSec = Double(nsText.substring(with: m.range(at: 2))) ?? 0
                var wFrac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let wpt = nsText.substring(with: m.range(at: 3))
                    if wpt.count == 3 { wFrac = (Double(wpt) ?? 0) / 1000 }
                    else if wpt.count == 2 { wFrac = (Double(wpt) ?? 0) / 100 }
                    else if wpt.count == 1 { wFrac = (Double(wpt) ?? 0) / 10 }
                }
                let currentTime = wMin * 60 + wSec + wFrac

                let nextPos = m.range.location + m.range.length
                let endOfText = (idx + 1 < matches.count) ? matches[idx+1].range.location : nsText.length
                let nextTextRange = NSRange(location: nextPos, length: endOfText - nextPos)
                let rawNext = nsText.substring(with: nextTextRange)
                var nextHasSpace = rawNext.hasSuffix(" ") || rawNext.hasSuffix("\t") || rawNext.hasSuffix("\u{00A0}")

                let nextText = rawNext.trimmingCharacters(in: .whitespaces)

                components.append((time: currentTime, text: nextText, space: nextHasSpace))

                lastPos = endOfText
            }

            if !components.isEmpty {

                lineWords = components.map { LyricWord(time: $0.time, text: $0.text, hasSpace: $0.space) }
            }
        }

        let cleanText = rawText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: #"\[\d{1,2}:\d{2}(?:[\.:,]\d{1,3})?\]"#, with: "", options: .regularExpression, range: nil)
            .trimmingCharacters(in: .whitespaces)

        lines.append(LyricLine(time: lineTime, text: cleanText, words: lineWords))
    }

    lines.sort { $0.time < $1.time }

    return ParsedLyrics(lines: lines, synced: !lines.isEmpty, copyright: response.copyright)
}
