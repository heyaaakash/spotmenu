// Native documentation previews. All account/music/device data below is fictional.
import AppKit
import Foundation
import SwiftUI

private final class PreviewProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Block all external requests, including any view-triggered queue refresh.
        let data = Data("{\"queue\":[]}".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main enum ScreenshotRenderer {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PlayMenuPreviews-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        for (screen, scheme) in [
            ("home", ColorScheme.dark), ("home", .light),
            ("compact", .dark), ("compact", .light),
            ("library", .dark), ("search", .dark),
            ("devices", .dark), ("settings", .dark), ("setup", .dark)
        ] {
            let suite = "PlayMenuPreviews.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [PreviewProtocol.self]
            let preferences = AppPreferences(defaults: defaults)
            preferences.isPresented = true
            preferences.animations = false
            preferences.appearance = scheme == .dark ? .dark : .light
            preferences.compact = screen == "compact"
            preferences.tab = screen == "library" ? .library : screen == "search" ? .search : .home
            preferences.filter = .songs
            preferences.showingDevices = screen == "devices"
            preferences.showingSettings = screen == "settings"
            preferences.recentSearches = ["Midnight Drive", "Soft Focus"]
            let service = SpotifyService(session: URLSession(configuration: configuration), cache: LibraryCache(directory: temporary), defaults: defaults, initialToken: "preview-fixture", restore: false, reconciliationDelay: nil, preferences: preferences)
            service.clientID = ""
            service.profile = Profile(display_name: "Alex", product: "premium")
            let colors: [(NSColor, NSColor)] = [
                (.init(red: 0.12, green: 0.1, blue: 0.3, alpha: 1), .init(red: 0.83, green: 0.44, blue: 0.68, alpha: 1)),
                (.init(red: 0.11, green: 0.29, blue: 0.29, alpha: 1), .init(red: 0.68, green: 0.86, blue: 0.54, alpha: 1)),
                (.init(red: 0.33, green: 0.16, blue: 0.1, alpha: 1), .init(red: 0.98, green: 0.71, blue: 0.39, alpha: 1)),
                (.init(red: 0.08, green: 0.2, blue: 0.4, alpha: 1), .init(red: 0.43, green: 0.75, blue: 0.94, alpha: 1)),
                (.init(red: 0.28, green: 0.15, blue: 0.3, alpha: 1), .init(red: 0.82, green: 0.69, blue: 0.9, alpha: 1))
            ]
            let names = ["Midnight Drive", "Soft Focus", "Golden Hour", "A Little Further", "After the Rain"]
            let artists = ["Nightfall", "Mellow Coast", "Daylight Club", "Open Skies", "Quiet Company"]
            let tracks = names.enumerated().map { index, name in
                let image = "https://example.invalid/playmenu-preview/\(index)"
                let album = Album(id: "sample-album-\(index)", name: name, uri: nil, images: [.init(url: image)], artists: nil)
                return Track(id: "sample-\(index)", name: name, uri: "spotify:track:sample\(index)", duration_ms: 224000 + index * 11000, artists: [.init(id: nil, name: artists[index], uri: nil)], album: album)
            }
            for (index, track) in tracks.enumerated() {
                let image = art(background: colors[index].0, accent: colors[index].1, variant: index)
                for points in [32, 42, 46, 64, 110] {
                    for scale in [1, 2] {
                        let pixels = points * scale
                        MemoryArtwork.cache.setObject(image, forKey: artworkKey(track.imageURL!, pixels) as NSString)
                    }
                }
            }
            service.player.apply(Playback(is_playing: true, progress_ms: 72000, repeat_state: "off", shuffle_state: false, item: tracks[0], device: Device(id: "sample-mac", name: "This Mac", type: "Computer", is_active: true, volume_percent: 65, supports_volume: true, is_restricted: false)))
            service.saved = tracks
            service.recent = Array(tracks.dropFirst())
            service.topTracks = [tracks[0], tracks[2]]
            service.player.savedIDs = Set(tracks.map(\.stableID))
            let playlistNames = ["Late Night", "Deep Focus", "Slow Mornings", "On the Move"]
            service.playlists = playlistNames.enumerated().map { index, name in
                Playlist(id: "sample-playlist-\(index)", name: name, uri: nil, description: nil, images: tracks[index].album?.images)
            }
            preferences.pinnedIDs = Set(service.playlists.prefix(3).map(\.stableID))
            if screen == "search" {
                preferences.query = "Midnight"
                service.search = SearchResults(tracks: Page(items: [tracks[0], tracks[3], tracks[4]], next: nil, total: 3), artists: nil, albums: Page(items: [tracks[0].album!], next: nil, total: 1), playlists: nil)
            }
            service.devices = [
                .init(id: "sample-mac", name: "This Mac", type: "Computer", is_active: true, volume_percent: 65, supports_volume: true, is_restricted: false),
                .init(id: "sample-speaker", name: "Living Room", type: "Speaker", is_active: false, volume_percent: 40, supports_volume: true, is_restricted: false),
                .init(id: "sample-phone", name: "iPhone", type: "Smartphone", is_active: false, volume_percent: 70, supports_volume: true, is_restricted: false)
            ]
            if screen == "setup" { service.connected = false }
            let mode: PopoverMode = preferences.compact ? .compact : .expanded
            let size = PopoverLayout.size(mode)
            let view = ContentView(mode: mode).environmentObject(service).environmentObject(service.player).environmentObject(preferences)
                .environment(\.colorScheme, scheme).environment(\.motionReduced, true).environment(\.displayScale, 2)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentViewController = host
            host.view.frame = NSRect(origin: .zero, size: size)
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { throw PreviewError.render }
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.render }
            let filename = "\(screen)-\(scheme == .dark ? "dark" : "light").png"
            try png.write(to: output.appendingPathComponent(filename))
            print("Rendered \(filename): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
            window.close()
        }
    }

    @MainActor private static func art(background: NSColor, accent: NSColor, variant: Int) -> NSImage {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)
        background.setFill(); bounds.fill()
        NSGradient(starting: background, ending: accent.withAlphaComponent(0.75))!.draw(in: bounds, angle: 45)
        for ring in 0..<6 {
            accent.withAlphaComponent(CGFloat(0.1 + Double(ring) * 0.04)).setStroke()
            let diameter = CGFloat(60 + ring * 32)
            let oval = NSBezierPath(ovalIn: NSRect(x: 128 - diameter / 2 + CGFloat(variant * 8), y: 100 - diameter / 2, width: diameter, height: diameter))
            oval.lineWidth = 3; oval.stroke()
        }
        accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 103, y: 85, width: 50, height: 50)).fill()
        image.unlockFocus()
        return image
    }
    private enum PreviewError: Error { case render }
}
