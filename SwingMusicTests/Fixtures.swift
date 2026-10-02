import Foundation
@testable import Swing_Music_Client

enum Fixtures {
    static func track(_ hash: String, image: String = "cover.webp", disc: Int? = nil, trackno: Int? = nil) -> Track {
        var json: [String: Any] = ["trackhash": hash, "title": "Track \(hash)", "image": image]
        if let disc { json["disc"] = disc }
        if let trackno { json["track"] = trackno }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Track.self, from: data)
    }

    static func group(_ id: String, _ kind: DownloadManager.DownloadGroup.Kind, _ hashes: [String]) -> DownloadManager.DownloadGroup {
        DownloadManager.DownloadGroup(id: id, kind: kind, name: id, image: "", trackHashes: hashes)
    }

    // Shaped like GET /artist/<hash>?tracklimit=5&all=true. The compilation reuses the first album's cover.
    static let artistResponse = Data("""
    {
      "artist": {"artisthash": "a1", "name": "The Beatles", "image": "a1.webp", "trackcount": 3, "albumcount": 3},
      "tracks": [
        {"trackhash": "t2", "title": "Help!", "album": "Help!", "albumhash": "al1", "image": "al1.webp"},
        {"trackhash": "t1", "title": "Yesterday", "album": "Help!", "albumhash": "al1", "image": "al1.webp"}
      ],
      "albums": {
        "albums": [{"albumhash": "al1", "title": "Help!", "image": "al1.webp"}],
        "singles_and_eps": [{"albumhash": "al2", "title": "Hey Jude", "image": "al2.webp"}],
        "appearances": [],
        "compilations": [{"albumhash": "al3", "title": "1", "image": "al1.webp"}],
        "artistname": "The Beatles"
      },
      "stats": [{"cssclass": "played", "value": "12", "text": "plays"}]
    }
    """.utf8)

    // Shaped like GET /artist/<hash>/tracks: a plain array, most played first.
    static let artistTracksResponse = Data("""
    [
      {"trackhash": "t2", "title": "Help!", "albumhash": "al1", "image": "al1.webp"},
      {"trackhash": "t1", "title": "Yesterday", "albumhash": "al1", "image": "al1.webp"},
      {"trackhash": "t3", "title": "Hey Jude", "albumhash": "al2", "image": "al2.webp"}
    ]
    """.utf8)
}
