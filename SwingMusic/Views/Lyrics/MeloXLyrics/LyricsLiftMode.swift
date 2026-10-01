import Foundation

enum LyricsLiftMode: String, CaseIterable, Identifiable, Sendable {
    case word
    case character

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word:
            "Per word"
        case .character:
            "Per character"
        }
    }
}
