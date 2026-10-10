import AppKit
import Combine
import Foundation
import Network

// Spotify's desktop broadcast is an optional hint, not an authenticated API.
// Bound and validate its metadata; reconcile device details against Spotify Connect.
struct DesktopPlaybackEvent: Sendable {
    enum State: String, Sendable { case playing, paused, stopped }
    let state: State
    let uri: String?
    let name: String?
    let artist: String?
    let album: String?
    let duration: Int?
    let position: Int?

    init?(_ info: [AnyHashable: Any]) {
        guard let raw = info["Player State"] as? String, raw.count <= 32,
              let state = State(rawValue: raw.lowercased()) else { return nil }
        self.state = state
        func text(_ key: String, limit: Int = 2048) -> String? {
            guard let value = info[key] as? String, !value.isEmpty, value.count <= limit,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return value
        }
        let candidate = text("Track ID", limit: 1024)
        uri = candidate.flatMap { value in
            let prefix = "spotify:track:"
            if value.hasPrefix(prefix) {
                let id = value.dropFirst(prefix.count)
                return !id.isEmpty && id.count <= 64 && id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ? value : nil
            }
            return value.hasPrefix("spotify:local:") && value.count > 14 && !value.contains(where: { $0.isWhitespace }) ? value : nil
        }
        name = text("Name"); artist = text("Artist"); album = text("Album")
        func number(_ key: String, scale: Double = 1) -> Int? {
            guard let value = info[key] as? NSNumber else { return nil }
            let converted = value.doubleValue * scale
            guard converted.isFinite, converted >= 0, converted <= 86_400_000 else { return nil }
            return Int(converted)
        }
        duration = number("Duration") // Desktop broadcast duration is milliseconds.
        position = number("Playback Position", scale: 1000) // Position is seconds.
    }

    func applying(to previous: Playback?) -> Playback? {
        if state == .stopped {
            guard var previous else { return nil }
            previous.is_playing = false; previous.progress_ms = 0
            return previous
        }
        let sameTrack = uri == nil || uri == previous?.item?.uri
        let track: Track
        if sameTrack, let existing = previous?.item { track = existing }
        else {
            guard let uri, let name else { return nil }
            let id = uri.hasPrefix("spotify:track:") ? String(uri.dropFirst(14)) : nil
            track = Track(id: id, name: name, uri: uri, duration_ms: duration,
                          artists: artist.map { [Artist(id: nil, name: $0, uri: nil)] },
                          album: album.map { Album(id: nil, name: $0, uri: nil, images: nil, artists: nil) })
        }
        let progress = position ?? (sameTrack ? previous?.progress_ms ?? 0 : 0)
        return Playback(is_playing: state == .playing, progress_ms: max(0, min(progress, track.duration_ms ?? 86_400_000)),
                        repeat_state: previous?.repeat_state, shuffle_state: previous?.shuffle_state, item: track,
                        device: previous?.device?.type == "Computer" ? previous?.device : nil)
    }

    func agrees(with playback: Playback?) -> Bool {
        if state == .stopped { return playback?.is_playing != true }
        return playback?.is_playing == (state == .playing) && (uri == nil || playback?.item?.uri == uri)
    }
}

// One monitor runs for the app's lifetime, independently of popover presentation.
// Waking the sleep never cancels a fetch; hints received during it queue one follow-up.
@MainActor final class PlaybackMonitor {
    private let service: SpotifyService
    private let observeSystemEvents: Bool
    private let pollInterval: Duration?
    private var subscriptions = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var network: NWPathMonitor?
    private var needsRefresh = false
    private var generation = 0

    init(service: SpotifyService, observeSystemEvents: Bool = true, pollInterval: Duration? = nil) {
        self.service = service; self.observeSystemEvents = observeSystemEvents; self.pollInterval = pollInterval
    }
    func start() {
        guard pollingTask == nil else { return }
        generation += 1
        let generation = self.generation
        service.$connected.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] connected in if connected { self?.refreshSoon() } }.store(in: &subscriptions)
        service.preferences.$isPresented.dropFirst().filter { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        if observeSystemEvents {
            DistributedNotificationCenter.default().publisher(for: .init("com.spotify.client.PlaybackStateChanged"))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    self?.receiveDesktopEvent(notification.userInfo.flatMap(DesktopPlaybackEvent.init))
                }.store(in: &subscriptions)
            let workspace = NSWorkspace.shared.notificationCenter
            workspace.publisher(for: NSWorkspace.didWakeNotification).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspace.publisher(for: name).receive(on: DispatchQueue.main)
                    .sink { [weak self] notification in
                        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                           app.bundleIdentifier == "com.spotify.client" { self?.refreshSoon() }
                    }.store(in: &subscriptions)
            }
            let network = NWPathMonitor()
            network.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { Task { @MainActor [weak self] in self?.refreshSoon() } }
            }
            network.start(queue: DispatchQueue(label: "com.playmenu.playback-network"))
            self.network = network
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, generation == self.generation else { return }
                self.needsRefresh = false
                await self.service.refreshPlayback()
                guard !Task.isCancelled else { return }
                if self.needsRefresh { continue }
                let serviceDelay = self.service.playbackPollingDelay
                let delay = min(self.pollInterval ?? serviceDelay, serviceDelay)
                let sleep = Task<Void, Never> { try? await Task.sleep(for: delay) }
                self.sleepTask = sleep
                await sleep.value
                if generation == self.generation { self.sleepTask = nil }
            }
        }
    }
    func receiveDesktopEvent(_ event: DesktopPlaybackEvent?) {
        guard pollingTask != nil else { return }
        if let event { service.receiveDesktopPlayback(event) }
        refreshSoon()
    }
    func refreshSoon() {
        guard pollingTask != nil else { return }
        needsRefresh = true; sleepTask?.cancel()
    }
    func stop() {
        generation += 1
        pollingTask?.cancel(); pollingTask = nil
        sleepTask?.cancel(); sleepTask = nil
        network?.cancel(); network = nil
        subscriptions.removeAll(); needsRefresh = false
    }
}
