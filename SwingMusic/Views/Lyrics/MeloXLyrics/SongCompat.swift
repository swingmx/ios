typealias Song = Track

extension Track {
    var name: String { title }
    var artistText: String { allArtists }
}

extension Track {
    var durationMS: Int { duration * 1000 }
    var isPodcastProgram: Bool { false }
}
