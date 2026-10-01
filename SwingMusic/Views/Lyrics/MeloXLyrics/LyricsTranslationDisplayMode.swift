import Foundation

enum LyricsTranslationDisplayMode: String, CaseIterable, Identifiable {
    case focusedLine
    case allLines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusedLine:
            "Focused line only"
        case .allLines:
            "All lines"
        }
    }
}
