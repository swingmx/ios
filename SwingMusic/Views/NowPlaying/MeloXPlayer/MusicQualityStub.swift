enum MusicQuality: String, CaseIterable, Identifiable, Hashable {
    case standard
    var id: String { rawValue }
    var title: String { "Standard" }
}
