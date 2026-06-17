import Foundation

struct TwitchCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let boxArtURL: URL?
    let viewerCount: Int?
}
