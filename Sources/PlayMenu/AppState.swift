import Foundation
import Combine

enum AppTab: String, CaseIterable {
    case home = "Home", search = "Search", library = "Library", queue = "Queue"
    var icon: String {
        switch self { case .home: "house.fill"; case .search: "magnifyingglass"; case .library: "square.stack.fill"; case .queue: "text.line.first.and.arrowtriangle.forward" }
    }
}
enum LibraryFilter: String, CaseIterable { case all = "All", playlists = "Playlists", songs = "Liked songs", pinned = "Pinned" }
enum SearchFilter: String, CaseIterable { case all = "All", tracks = "Tracks", albums = "Albums", playlists = "Playlists", artists = "Artists" }
enum AppearanceMode: String, CaseIterable { case auto = "Auto", light = "Light", dark = "Dark" }

@MainActor final class AppPreferences: ObservableObject {
    let defaults: UserDefaults
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearanceMode") } }
    @Published var continuousPlayback: Bool { didSet { defaults.set(continuousPlayback, forKey: "continuousPlayback") } }
    @Published var animations: Bool { didSet { defaults.set(animations, forKey: "animationsEnabled") } }
    @Published var desktopFallback: Bool { didSet { defaults.set(desktopFallback, forKey: "desktopFallback") } }
    @Published var rememberSearches: Bool { didSet { defaults.set(rememberSearches, forKey: "rememberSearches"); if !rememberSearches { recentSearches = [] } } }
    @Published var playingIcon: Bool { didSet { defaults.set(playingIcon, forKey: "playingIcon") } }
    @Published var liveVisualizer: Bool { didSet { defaults.set(liveVisualizer, forKey: "liveVisualizer") } }
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compactMode") } }
    @Published var tab: AppTab { didSet { defaults.set(tab.rawValue, forKey: "selectedTab") } }
    @Published var filter: LibraryFilter { didSet { defaults.set(filter.rawValue, forKey: "libraryFilter") } }
    @Published var pinnedIDs: Set<String> { didSet { defaults.set(Array(pinnedIDs), forKey: "pinnedPlaylists") } }
    @Published var recentSearches: [String] { didSet { defaults.set(recentSearches, forKey: "recentSearches") } }
    @Published var scrollAnchors: [String: String] { didSet { defaults.set(scrollAnchors, forKey: "scrollAnchors") } }
    @Published var query = ""
    @Published var searchFilter: SearchFilter = .all
    @Published var selection = 0
    @Published var focusSearchRequest = 0
    @Published var showingSettings = false
    @Published var showingDevices = false
    @Published var isPresented = false
    @Published var adjustingSlider = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .auto
        continuousPlayback = defaults.object(forKey: "continuousPlayback") as? Bool ?? true
        animations = defaults.object(forKey: "animationsEnabled") as? Bool ?? true
        desktopFallback = defaults.object(forKey: "desktopFallback") as? Bool ?? true
        rememberSearches = defaults.object(forKey: "rememberSearches") as? Bool ?? true
        playingIcon = defaults.object(forKey: "playingIcon") as? Bool ?? true
        liveVisualizer = defaults.bool(forKey: "liveVisualizer")
        compact = defaults.bool(forKey: "compactMode")
        tab = AppTab(rawValue: defaults.string(forKey: "selectedTab") ?? "") ?? .home
        filter = LibraryFilter(rawValue: defaults.string(forKey: "libraryFilter") ?? "") ?? .all
        pinnedIDs = Set(defaults.stringArray(forKey: "pinnedPlaylists") ?? [])
        recentSearches = defaults.stringArray(forKey: "recentSearches") ?? []
        scrollAnchors = defaults.dictionary(forKey: "scrollAnchors") as? [String: String] ?? [:]
    }
    func togglePin(_ playlist: Playlist) { if pinnedIDs.contains(playlist.stableID) { pinnedIDs.remove(playlist.stableID) } else { pinnedIDs.insert(playlist.stableID) } }
    func rememberSearch(_ text: String) {
        guard rememberSearches else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        recentSearches.removeAll { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
        recentSearches.insert(value, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
    }
    func focusSearch() { compact = false; tab = .search; focusSearchRequest += 1 }
    func entries(from results: SearchResults?) -> [SearchEntry] {
        (results?.entries ?? []).filter { entry in
            switch (searchFilter, entry) {
            case (.all, _), (.tracks, .track), (.albums, .album), (.playlists, .playlist), (.artists, .artist): true
            default: false
            }
        }
    }
}

@MainActor final class PlayerState: ObservableObject {
    @Published var playback: Playback?
    @Published var pendingCommands = 0
    @Published var transferringID: String?
    @Published var savedIDs: Set<String> = []
    @Published var volume: Double
    var revision = 0
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volume = defaults.object(forKey: "lastVolume") as? Double ?? 50
    }
    func setVolume(_ value: Double) {
        let clamped = min(100, max(0, value))
        guard clamped != volume else { return }
        volume = clamped; defaults.set(volume, forKey: "lastVolume")
    }
    func apply(_ value: Playback?) {
        if playback != value { playback = value }
        if let percent = value?.device?.volume_percent { setVolume(Double(percent)) }
    }
    func isSaved(_ track: Track) -> Bool { savedIDs.contains(track.stableID) }
}

struct Notice: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    var undo: (@MainActor () -> Void)?
}

enum Recovery: Equatable { case retry, reconnect, device, wait }
