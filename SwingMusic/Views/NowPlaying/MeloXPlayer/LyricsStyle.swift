import Foundation

enum LyricsStyle: String, CaseIterable, Identifiable {
    case appleMusic
    case eva
    case textPV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .eva: "EVA"
        case .textPV: "Text PV"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusic: "quote.bubble"
        case .eva: "rectangle.split.3x1.fill"
        case .textPV: "textformat.size.larger"
        }
    }

    var description: String {
        switch self {
        case .appleMusic: "Scrolling lyrics with distance blur and word highlighting"
        case .eva: ""
        case .textPV: ""
        }
    }

    var usesMonochromePlayerBackground: Bool {
        switch self {
        case .eva, .textPV: true
        case .appleMusic: false
        }
    }
}
