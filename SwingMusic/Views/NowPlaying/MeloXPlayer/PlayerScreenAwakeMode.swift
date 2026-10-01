import Foundation

enum PlayerScreenAwakeMode: String, CaseIterable, Identifiable {
    case disabled
    case player
    case lyrics
    case hiddenLyricsInterface

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            "Off"
        case .player:
            "Player always on"
        case .lyrics:
            "Lyrics always on"
        case .hiddenLyricsInterface:
            "On when UI hidden"
        }
    }
}
