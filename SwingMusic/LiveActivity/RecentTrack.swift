import Foundation

public struct RecentTrack: Codable, Hashable {
    public let title: String
    public let artist: String
    public let imageData: Data?
    public let accentHex: String
}
