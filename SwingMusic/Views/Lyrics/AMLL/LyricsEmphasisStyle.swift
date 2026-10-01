import Foundation

enum LyricsEmphasisStyle: String, CaseIterable, Identifiable, Sendable {
    case meloX
    case amll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meloX: "MeloX"
        case .amll: "AMLL"
        }
    }
}
