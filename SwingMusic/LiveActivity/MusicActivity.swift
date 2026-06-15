import ActivityKit
import Foundation

struct MusicAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var album: String
        var playing: Bool
        var progress: Double
        var duration: Double
        var imageData: Data?
        var accentHex: String
    }
    var serverURL: String
}
