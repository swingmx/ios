import Foundation

extension ParsedLyrics {
    var meloXLines: [MXLyricLine] {
        let all = lines
        return all.enumerated().map { index, line in
            let lineEnd: TimeInterval? = index + 1 < all.count ? all[index + 1].time : nil

            var syllables: [LyricSyllable] = []
            if let words = line.words, !words.isEmpty {
                syllables = words.enumerated().compactMap { wordIndex, word in
                    guard !word.text.isEmpty else { return nil }
                    let next: TimeInterval
                    if wordIndex + 1 < words.count {
                        next = words[wordIndex + 1].time
                    } else {
                        next = lineEnd ?? (word.time + 1)
                    }
                    return LyricSyllable(
                        text: word.hasSpace ? word.text + " " : word.text,
                        startTime: word.time,
                        endTime: max(next, word.time)
                    )
                }
            }

            let lineEndTime = syllables.map(\.endTime).max() ?? lineEnd

            return MXLyricLine(
                time: line.time,
                duration: lineEndTime.map { max($0 - line.time, 0) },
                text: line.text,
                syllables: syllables
            )
        }
    }
}
