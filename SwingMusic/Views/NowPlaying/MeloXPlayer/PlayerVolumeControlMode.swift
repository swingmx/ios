import Foundation

enum PlayerVolumeControlMode: String, CaseIterable, Identifiable {
    case hidden
    case independent
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: "Hidden"
        case .independent: "Independent"
        case .system: "System volume"
        }
    }

    var description: String {
        switch self {
        case .hidden:
            "The player hides the volume slider; the system controls volume."
        case .independent:
            "Player volume is independent from system volume."
        case .system:
            "The player shows the system volume slider."
        }
    }
}
