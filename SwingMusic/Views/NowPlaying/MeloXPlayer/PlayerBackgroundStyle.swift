import Foundation

enum PlayerBackgroundStyle: String, CaseIterable, Identifiable {
    case flowingLight
    case blurredArtwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flowingLight:
            "Flowing light"
        case .blurredArtwork:
            "Blurred artwork"
        }
    }
}
