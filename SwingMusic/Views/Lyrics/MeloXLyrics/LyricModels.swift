import Foundation

struct LyricSyllable: Identifiable, Hashable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    var id: String {
        "\(startTime)-\(endTime)-\(text)"
    }
}

struct MXLyricLine: Identifiable, Hashable {
    let time: TimeInterval
    let duration: TimeInterval?
    let text: String
    let syllables: [LyricSyllable]
    let romanization: String?
    let romanizationSyllables: [LyricSyllable]
    let translation: String?

    init(
        time: TimeInterval,
        duration: TimeInterval? = nil,
        text: String,
        syllables: [LyricSyllable] = [],
        romanization: String? = nil,
        romanizationSyllables: [LyricSyllable] = [],
        translation: String? = nil
    ) {
        self.time = time
        self.duration = duration
        self.text = text
        self.syllables = syllables
        self.romanization = romanization
        self.romanizationSyllables = romanizationSyllables
        self.translation = translation
    }

    var id: String {
        "\(time)-\(text)"
    }

    var isSyllableSynced: Bool {
        !syllables.isEmpty
    }

    var hasTranslation: Bool {
        guard let translation else { return false }
        return !translation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var hasRomanization: Bool {
        guard let romanization else { return false }
        return !romanization
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func makePseudoSyllables() -> [LyricSyllable] {
        guard syllables.isEmpty,
              let duration,
              duration > 0 else { return [] }

        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        let characterDuration = duration / Double(characters.count)
        return characters.enumerated().map { index, character in
            let startTime = time + Double(index) * characterDuration
            return LyricSyllable(
                text: String(character),
                startTime: startTime,
                endTime: startTime + characterDuration
            )
        }
    }

    func attachingTranslation(_ translation: String?) -> MXLyricLine {
        MXLyricLine(
            time: time,
            duration: duration,
            text: text,
            syllables: syllables,
            romanization: romanization,
            romanizationSyllables: romanizationSyllables,
            translation: translation
        )
    }

    func attachingRomanization(
        _ romanization: String?,
        romanizationSyllables: [LyricSyllable] = []
    ) -> MXLyricLine {
        MXLyricLine(
            time: time,
            duration: duration,
            text: text,
            syllables: syllables,
            romanization: romanization,
            romanizationSyllables: romanizationSyllables,
            translation: translation
        )
    }

    func accessibilityText(
        includingTranslation: Bool,
        includingRomanization: Bool = false
    ) -> String {
        var components = [text]
        if includingRomanization, hasRomanization,
           let romanization {
            components.append("Pronunciation: \(romanization)")
        }
        if includingTranslation, hasTranslation,
           let translation {
            components.append("Translation: \(translation)")
        }
        return components.joined(separator: "，")
    }
}
