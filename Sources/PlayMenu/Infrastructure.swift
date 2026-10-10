import AppKit
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

struct LibrarySnapshot: Codable, Sendable {
    let clientID: String
    let profile: Profile?
    let playlists: [Playlist]
    let saved: [Track]
    let recent: [Track]
    let topTracks: [Track]
    let playlistNext: String?
    let savedNext: String?
    let savedIDs: Set<String>
    let date: Date
}

actor LibraryCache {
    static let live = LibraryCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SpotMenu"))
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func load(clientID: String) -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("library.json")),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data), snapshot.clientID == clientID else { return nil }
        return snapshot
    }
    func save(_ snapshot: LibrarySnapshot) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }
    func clear() { try? FileManager.default.removeItem(at: directory.appendingPathComponent("library.json")) }
}

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SpotMenu/Artwork")
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var writes = 0

    func thumbnail(url: URL, pixels: Int) async -> Data? {
        let key = artworkKey(url, pixels)
        let file = directory.appendingPathComponent(key + ".png")
        if let data = try? Data(contentsOf: file) { return data }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> Data? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return downsample(data, pixels: pixels)
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        if let data {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            writes += 1
            if writes % 40 == 0 { trim() }
        }
        return data
    }
    private func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let value = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, value.fileSize ?? 0, value.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where size > 50 * 1024 * 1024 { try? FileManager.default.removeItem(at: entry.0); size -= entry.1 }
    }
}

func artworkKey(_ url: URL, _ pixels: Int) -> String {
    SHA256.hash(data: Data("\(url.absoluteString):\(pixels)".utf8)).map { String(format: "%02x", $0) }.joined()
}

func downsample(_ data: Data, pixels: Int) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
}

@MainActor enum MemoryArtwork {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 30 * 1024 * 1024
        cache.countLimit = 240
        return cache
    }()
}

// Serial execution keeps local Apple Events off the UI thread.
actor LocalSpotify {
    func execute(_ command: String) async -> Bool {
        let script = "tell application id \"com.spotify.client\" to \(command)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                    if process.isRunning { process.terminate() }
                }
            } catch { continuation.resume(returning: false) }
        }
    }
}

enum Performance {
    static let logger = Logger(subsystem: "com.playmenu.app", category: "Responsiveness")
    static func record(_ name: String, since start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now)
        logger.debug("\(name, privacy: .public): \(String(describing: elapsed), privacy: .public)")
    }
}

enum PopoverMode: Equatable { case compact, expanded }

// A transition token prevents a scheduled reopening after a newer switch or dismissal.
struct PresentationState {
    private(set) var generation = 0
    private(set) var desired: PopoverMode = .expanded
    mutating func request(_ mode: PopoverMode) -> Int { desired = mode; generation += 1; return generation }
    mutating func dismiss() { generation += 1 }
    func accepts(_ token: Int, mode: PopoverMode) -> Bool { token == generation && desired == mode }
}
