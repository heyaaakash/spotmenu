import Foundation

protocol SpotifyIdentifiable { var stableID: String { get } }
extension Track: SpotifyIdentifiable {}
extension Playlist: SpotifyIdentifiable {}

struct SpotifyImage: Codable, Hashable, Sendable { let url: String }
struct Artist: Codable, Identifiable, Hashable, Sendable {
    let id: String?
    let name: String
    let uri: String?
    var stableID: String { id ?? name }
}
struct Album: Codable, Identifiable, Hashable, Sendable {
    let id: String?
    let name: String
    let uri: String?
    let images: [SpotifyImage]?
    let artists: [Artist]?
    var stableID: String { id ?? name }
    var imageURL: URL? { images?.first.flatMap { URL(string: $0.url) } }
}
struct Track: Codable, Identifiable, Hashable, Sendable {
    let id: String?
    let name: String
    let uri: String?
    let duration_ms: Int?
    let artists: [Artist]?
    let album: Album?
    var stableID: String { id ?? uri ?? name }
    var artistLine: String { artists?.map(\.name).joined(separator: ", ") ?? "Unknown artist" }
    var imageURL: URL? { album?.imageURL }
}
struct Playlist: Codable, Identifiable, Hashable, Sendable {
    let id: String?
    let name: String
    let uri: String?
    let description: String?
    let images: [SpotifyImage]?
    var stableID: String { id ?? name }
    var imageURL: URL? { images?.first.flatMap { URL(string: $0.url) } }
}
struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let next: String?
    let total: Int?
}
struct SavedTrack: Decodable, Sendable { let track: Track }
struct PlayableTrack: Decodable, Sendable { let uri: String?; let is_playable: Bool? }
struct RecentTrack: Decodable, Sendable { let track: Track }
struct PlaylistItem: Decodable, Sendable { let item: Track?; let track: Track?; var resolved: Track? { item ?? track } }
struct SearchResults: Decodable, Sendable { let tracks: Page<Track>?; let artists: Page<Artist>?; let albums: Page<Album>?; let playlists: Page<Playlist?>? }
struct Playback: Codable, Equatable, Sendable {
    var is_playing: Bool
    var progress_ms: Int?
    var repeat_state: String?
    var shuffle_state: Bool?
    var item: Track?
    var device: Device?
}
struct Device: Codable, Identifiable, Equatable, Sendable {
    let id: String?
    let name: String
    let type: String
    var is_active: Bool
    var volume_percent: Int?
    let supports_volume: Bool?
    let is_restricted: Bool?
    var stableID: String { id ?? name }
}
struct DeviceList: Decodable, Sendable { let devices: [Device] }
struct QueueResult: Decodable, Sendable { let queue: [Track] }
struct Profile: Codable, Sendable { let display_name: String?; let product: String? }
struct TokenResponse: Decodable, Sendable { let access_token: String; let token_type: String; let expires_in: Int; let refresh_token: String? }

enum APIError: LocalizedError {
    case message(String)
    case expired, offline, noDevice, forbidden, ambiguousResponse, rateLimited(Int)
    var allowsDesktopFallback: Bool {
        switch self {
        case .noDevice, .forbidden, .message: true
        case .expired, .offline, .ambiguousResponse, .rateLimited: false
        }
    }
    var errorDescription: String? {
        switch self {
        case .message(let value): value
        case .expired: "Your Spotify session expired. Reconnect to continue."
        case .offline: "You're offline. Your cached library is still available."
        case .noDevice: "Choose a device or open Spotify to start playing."
        case .forbidden: "Spotify denied this action. Check your account's Premium and app access."
        case .ambiguousResponse: "Spotify’s response was unclear. Refresh playback before retrying."
        case .rateLimited(let seconds): "Spotify needs a breather. Try again in \(seconds) seconds."
        }
    }
}

func allowsDesktopFallback(after error: Error) -> Bool {
    (error as? APIError)?.allowsDesktopFallback ?? false
}

enum SearchEntry: Identifiable, Sendable {
    case track(Track), album(Album), playlist(Playlist), artist(Artist)
    var id: String {
        switch self {
        case .track(let value): "track:\(value.stableID)"
        case .album(let value): "album:\(value.stableID)"
        case .playlist(let value): "playlist:\(value.stableID)"
        case .artist(let value): "artist:\(value.stableID)"
        }
    }
    var title: String {
        switch self { case .track(let v): v.name; case .album(let v): v.name; case .playlist(let v): v.name; case .artist(let v): v.name }
    }
    var subtitle: String {
        switch self {
        case .track(let v): v.artistLine
        case .album(let v): "Album · \(v.artists?.map(\.name).joined(separator: ", ") ?? "")"
        case .playlist: "Playlist"
        case .artist: "Artist · Open in Spotify"
        }
    }
    var imageURL: URL? {
        switch self { case .track(let v): v.imageURL; case .album(let v): v.imageURL; case .playlist(let v): v.imageURL; case .artist: nil }
    }
}

extension SearchResults {
    var entries: [SearchEntry] {
        (tracks?.items.map(SearchEntry.track) ?? []) + (albums?.items.map(SearchEntry.album) ?? []) +
        (playlists?.items.compactMap { $0 }.map(SearchEntry.playlist) ?? []) + (artists?.items.map(SearchEntry.artist) ?? [])
    }
}
