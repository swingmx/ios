import NaturalLanguage

enum LyricWordSegmenter {
    static func blockRanges(in text: String) -> [Range<Int>] {
        guard !text.isEmpty else { return [] }

        let textLength = text.count
        let phraseRanges = nonWhitespaceRanges(in: text)
        let segmentedRanges = phraseRanges.flatMap {
            tokenRanges(in: text, phraseRange: $0)
        }
        guard !segmentedRanges.isEmpty else {
            return [0..<textLength]
        }

        return rangesCoveringWhitespace(
            between: segmentedRanges,
            textLength: textLength
        )
    }

    private static func nonWhitespaceRanges(
        in text: String
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var phraseStart: String.Index?

        for index in text.indices {
            if text[index].isWhitespace {
                if let start = phraseStart {
                    result.append(start..<index)
                    phraseStart = nil
                }
            } else if phraseStart == nil {
                phraseStart = index
            }
        }

        if let phraseStart {
            result.append(phraseStart..<text.endIndex)
        }
        return result
    }

    private static func tokenRanges(
        in text: String,
        phraseRange: Range<String.Index>
    ) -> [Range<Int>] {
        let phrase = String(text[phraseRange])
        let phraseOffset = text.distance(
            from: text.startIndex,
            to: phraseRange.lowerBound
        )
        let phraseLength = phrase.count
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = phrase

        var rawRanges: [Range<Int>] = []
        tokenizer.enumerateTokens(
            in: phrase.startIndex..<phrase.endIndex
        ) { tokenRange, _ in
            let lowerBound = phrase.distance(
                from: phrase.startIndex,
                to: tokenRange.lowerBound
            )
            let upperBound = phrase.distance(
                from: phrase.startIndex,
                to: tokenRange.upperBound
            )
            if lowerBound < upperBound {
                rawRanges.append(
                    (phraseOffset + lowerBound)..<(phraseOffset + upperBound)
                )
            }
            return true
        }

        let phraseCharacterRange =
            phraseOffset..<(phraseOffset + phraseLength)
        return rangesCoveringPunctuation(
            between: rawRanges,
            phraseRange: phraseCharacterRange
        )
    }

    private static func rangesCoveringPunctuation(
        between tokenRanges: [Range<Int>],
        phraseRange: Range<Int>
    ) -> [Range<Int>] {
        let sortedRanges = tokenRanges
            .filter {
                $0.lowerBound >= phraseRange.lowerBound
                    && $0.upperBound <= phraseRange.upperBound
            }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard let firstRange = sortedRanges.first else {
            return [phraseRange]
        }

        var result = [
            phraseRange.lowerBound..<firstRange.upperBound
        ]
        for range in sortedRanges.dropFirst() {
            guard let previous = result.last,
                  range.lowerBound >= previous.upperBound else {
                continue
            }
            result[result.count - 1] =
                previous.lowerBound..<range.lowerBound
            result.append(range)
        }

        if let last = result.last {
            result[result.count - 1] =
                last.lowerBound..<phraseRange.upperBound
        }
        return result
    }

    private static func rangesCoveringWhitespace(
        between tokenRanges: [Range<Int>],
        textLength: Int
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []

        for range in tokenRanges.sorted(by: {
            $0.lowerBound < $1.lowerBound
        }) {
            guard range.lowerBound < range.upperBound else { continue }

            if let previous = result.last {
                guard range.lowerBound >= previous.upperBound else {
                    continue
                }
                result[result.count - 1] =
                    previous.lowerBound..<range.lowerBound
                result.append(range)
            } else {
                result.append(0..<range.upperBound)
            }
        }

        if let last = result.last {
            result[result.count - 1] =
                last.lowerBound..<textLength
        }
        return result
    }
}
