import Foundation
import ImageIO
import AppKit
import SwiftUI

private struct StubResponse: Sendable {
    var status = 200
    var json = ""
    var delay: Duration = .zero
    var headers: [String: String] = [:]
    var failure: URLError.Code? = nil
}
private actor StubNetwork {
    static let shared = StubNetwork()
    var requests: [URLRequest] = []
    var handler: @Sendable (URLRequest) -> StubResponse = { _ in .init(status: 204) }
    private var playbackResponses: [StubResponse]?
    func reset(_ handler: @escaping @Sendable (URLRequest) -> StubResponse) { requests = []; self.handler = handler; playbackResponses = nil }
    func reset(playbackResponses: [StubResponse]) { requests = []; handler = { _ in .init(status: 204) }; self.playbackResponses = playbackResponses }
    func response(_ request: URLRequest) -> StubResponse {
        requests.append(request)
        if request.url?.path == "/v1/me/player", let first = playbackResponses?.first {
            if playbackResponses!.count > 1 { playbackResponses!.removeFirst() }
            return first
        }
        return handler(request)
    }
    func history() -> [URLRequest] { requests }
}
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        responseTask = Task {
            let value = await StubNetwork.shared.response(request)
            do { try await Task.sleep(for: value.delay); try Task.checkCancellation() } catch { return }
            if let code = value.failure { client?.urlProtocol(self, didFailWithError: URLError(code)); return }
            let response = HTTPURLResponse(url: request.url!, statusCode: value.status, httpVersion: "HTTP/1.1", headerFields: value.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(value.json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

private actor MockAudioCapture: AudioCapturing {
    var starts = 0
    var stops = 0
    var callbacks: [@Sendable (AudioFrame) -> Void] = []
    var failure = false
    func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) async throws {
        starts += 1; callbacks.append(onFrame)
        try await Task.sleep(for: .milliseconds(20))
        if failure { throw AudioCaptureError.spotifyNotRunning }
    }
    func stop() { stops += 1 }
    func emit(_ frame: AudioFrame, callback: Int = 0) { callbacks[callback](frame) }
    func setFailure(_ value: Bool = true) { failure = value }
    func counts() -> (Int, Int) { (starts, stops) }
}

@MainActor final class PlayMenuTests {
    private func fixture(capture: MockAudioCapture? = nil) -> (SpotifyService, UserDefaults, URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let name = "PlayMenuTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("fixture-client", forKey: "spotifyClientID")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let service = SpotifyService(session: URLSession(configuration: configuration), cache: LibraryCache(directory: directory), defaults: defaults, initialToken: "fixture-token-\(name)", restore: false, reconciliationDelay: nil, visualizer: AudioVisualizer(capture: capture ?? MockAudioCapture()))
        return (service, defaults, directory)
    }
    private var song: Track { Track(id: "one", name: "First song", uri: "spotify:track:one", duration_ms: 240000, artists: [Artist(id: "artist", name: "Test Artist", uri: nil)], album: nil) }
    private func playback(_ song: Track, playing: Bool = true, progress: Int = 5000) -> Playback { Playback(is_playing: playing, progress_ms: progress, repeat_state: "off", shuffle_state: false, item: song, device: nil) }
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        expect(condition())
    }
    private func query(_ request: URLRequest, _ name: String) -> String? { URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value }

    private var playingResponse: StubResponse {
        .init(json: #"{"is_playing":true,"progress_ms":1250,"item":{"id":"second","name":"Second song","uri":"spotify:track:second","duration_ms":200000,"album":{"name":"Test album","images":[{"url":"https://example.invalid/test-cover.png"}]}}}"#)
    }
    private var pausedResponse: StubResponse {
        .init(json: #"{"is_playing":false,"progress_ms":5000,"item":{"id":"one","name":"First song","uri":"spotify:track:one","duration_ms":240000}}"#)
    }
    private var desktopPlaying: DesktopPlaybackEvent {
        DesktopPlaybackEvent(["Player State": "Playing", "Track ID": "spotify:track:second", "Name": "Second song", "Artist": "Test Artist", "Album": "Test album", "Duration": 200000, "Playback Position": 1.25])!
    }
    private func waitForPlaybackRequests(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            let history = await StubNetwork.shared.history()
            if history.filter({ $0.url?.path == "/v1/me/player" }).count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        expect(false)
    }

    func testDesktopEventsUpdatePlaybackWithoutWaitingForTheAPI() {
        let (service, _, _) = fixture(); defer { service.disconnect() }
        service.player.apply(playback(song, playing: false))
        let start = ContinuousClock.now
        service.receiveDesktopPlayback(desktopPlaying)
        expect(start.duration(to: .now) < .milliseconds(100))
        expect(service.player.playback?.is_playing == true)
        expect(service.player.playback?.item?.uri == "spotify:track:second")
        expect(service.player.playback?.progress_ms == 1250)
        expect(service.player.playback?.item?.duration_ms == 200000)
        expect(service.player.revision == 1)
        service.receiveDesktopPlayback(DesktopPlaybackEvent(["Player State": "Paused"])!)
        expect(service.player.playback?.is_playing == false)
        service.receiveDesktopPlayback(DesktopPlaybackEvent(["Player State": "Stopped"])!)
        expect(service.player.playback?.progress_ms == 0)
        expect(DesktopPlaybackEvent(["Player State": "Unrecognized"]) == nil)
        let malformed = DesktopPlaybackEvent(["Player State": "Playing", "Track ID": "https://example.invalid/command", "Duration": -1, "Playback Position": Double.infinity])!
        expect(malformed.uri == nil); expect(malformed.duration == nil); expect(malformed.position == nil)
        expect(DesktopPlaybackEvent(["Player State": "Playing", "Playback Position": Double.nan])?.position == nil)
        expect(DesktopPlaybackEvent(["Player State": "Playing", "Name": String(repeating: "x", count: 2049)])?.name == nil)
    }

    func testDesktopEventsDoNotOverrideAnActiveRemoteDeviceOrCommand() async throws {
        let (service, _, _) = fixture(); defer { service.disconnect() }
        var remote = playback(song)
        remote.device = Device(id: "phone", name: "Test phone", type: "Smartphone", is_active: true, volume_percent: 50, supports_volume: true, is_restricted: false)
        service.player.apply(remote)
        service.receiveDesktopPlayback(DesktopPlaybackEvent(["Player State": "Paused"])!)
        expect(service.player.playback == remote)
        service.player.apply(playback(song))
        service.player.pendingCommands = 1
        service.receiveDesktopPlayback(desktopPlaying)
        expect(service.player.playback?.item == song)
        service.player.pendingCommands = 0
        service.receiveDesktopPlayback(desktopPlaying)
        let stale = pausedResponse
        await StubNetwork.shared.reset { request in request.httpMethod == "GET" ? stale : .init(status: 204) }
        await service.shuffle(); await service.refreshPlayback()
        expect(service.player.playback?.item?.uri == "spotify:track:second")
        expect(service.player.playback?.is_playing == true)
        expect(service.player.playback?.shuffle_state == true)
        service.disconnect(); service.receiveDesktopPlayback(desktopPlaying)
        expect(service.player.playback == nil)
    }

    func testDesktopEventsSurviveStaleAndEmptyAPIResponses() async throws {
        var stale = pausedResponse; stale.delay = .milliseconds(100)
        await StubNetwork.shared.reset(playbackResponses: [stale, .init(status: 204), playingResponse])
        let (service, _, _) = fixture(); defer { service.disconnect() }
        service.player.apply(playback(song, playing: false))
        let request = Task { await service.refreshPlayback() }
        try await waitForPlaybackRequests(1)
        service.receiveDesktopPlayback(desktopPlaying)
        await request.value
        expect(service.player.playback?.is_playing == true)
        expect(service.player.playback?.item?.uri == "spotify:track:second")
        try await Task.sleep(for: .milliseconds(510))
        await service.refreshPlayback()
        expect(service.player.playback?.item?.uri == "spotify:track:second")
        try await Task.sleep(for: .milliseconds(510))
        await service.refreshPlayback()
        expect(service.player.playback?.item?.imageURL?.absoluteString == "https://example.invalid/test-cover.png")
        let history = await StubNetwork.shared.history()
        expect(history.first?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    func testSlowSavedStatusDoesNotBlockPlaybackRefresh() async throws {
        let response = playingResponse
        await StubNetwork.shared.reset { request in
            if request.url?.path == "/v1/me/player" { return response }
            return .init(json: "[false]", delay: .seconds(1))
        }
        let (service, _, _) = fixture(); defer { service.disconnect() }
        let start = ContinuousClock.now
        await service.refreshPlayback()
        expect(start.duration(to: .now) < .milliseconds(200))
        expect(service.player.playback?.is_playing == true)
        try await Task.sleep(for: .milliseconds(510))
        await service.refreshPlayback()
        let history = await StubNetwork.shared.history()
        let authorization = try require(history.first { $0.url?.path == "/v1/me/player" }?.value(forHTTPHeaderField: "Authorization"))
        // A cancelled URLProtocol callback from an earlier fixture may still finish
        // delivery. Count this service's requests rather than another session's.
        let ownRequests = history.filter { $0.value(forHTTPHeaderField: "Authorization") == authorization }
        expect(ownRequests.filter { $0.url?.path == "/v1/me/player" }.count == 2)
        expect(ownRequests.filter { $0.url?.path == "/v1/me/library/contains" }.count == 1)
    }

    func testBackgroundMonitorDetectsMusicWithTheMenuClosed() async throws {
        await StubNetwork.shared.reset(playbackResponses: [.init(status: 204), pausedResponse, playingResponse])
        let (service, _, _) = fixture()
        service.preferences.isPresented = false
        let monitor = PlaybackMonitor(service: service, observeSystemEvents: false, pollInterval: .milliseconds(25))
        defer { monitor.stop(); service.disconnect() }
        monitor.start(); monitor.start()
        try await waitUntil { service.player.playback?.is_playing == true }
        expect(!service.preferences.isPresented)
        expect(service.player.playback?.item?.uri == "spotify:track:second")
        let history = await StubNetwork.shared.history()
        expect(history.filter { $0.url?.path == "/v1/me/player" }.count == 3)
    }

    func testPlaybackHintsDuringAFetchQueueOneFollowUp() async throws {
        var stale = pausedResponse; stale.delay = .milliseconds(100)
        await StubNetwork.shared.reset(playbackResponses: [stale, playingResponse])
        let (service, _, _) = fixture()
        let monitor = PlaybackMonitor(service: service, observeSystemEvents: false, pollInterval: .seconds(60))
        defer { monitor.stop(); service.disconnect() }
        monitor.start()
        try await waitForPlaybackRequests(1)
        for _ in 0..<100 { monitor.receiveDesktopEvent(nil) }
        try await waitUntil { service.player.playback?.is_playing == true }
        let history = await StubNetwork.shared.history()
        expect(history.filter { $0.url?.path == "/v1/me/player" }.count == 2)
    }

    func testOpeningTheMenuWakesBackgroundPollingAndStopRemovesIt() async throws {
        await StubNetwork.shared.reset(playbackResponses: [.init(status: 204), playingResponse])
        let (service, _, _) = fixture()
        let monitor = PlaybackMonitor(service: service, observeSystemEvents: false)
        defer { monitor.stop(); service.disconnect() }
        monitor.start()
        try await waitForPlaybackRequests(1)
        service.preferences.isPresented = true
        try await waitUntil { service.player.playback?.is_playing == true }
        monitor.stop()
        let stopped = await StubNetwork.shared.history()
        try await Task.sleep(for: .milliseconds(550))
        let later = await StubNetwork.shared.history()
        expect(stopped.filter { $0.url?.path == "/v1/me/player" }.count == 2)
        expect(later.filter { $0.url?.path == "/v1/me/player" }.count == 2)
        monitor.start()
        try await waitForPlaybackRequests(3)
    }

    func testPlaybackMonitorRecoversFromNetworkFailureAutomatically() async throws {
        await StubNetwork.shared.reset(playbackResponses: [.init(failure: .timedOut), playingResponse])
        let (service, _, _) = fixture()
        let monitor = PlaybackMonitor(service: service, observeSystemEvents: false, pollInterval: .milliseconds(25))
        defer { monitor.stop(); service.disconnect() }
        monitor.start()
        try await waitUntil { service.offline }
        expect(service.playbackPollingDelay >= .seconds(1))
        try await waitUntil { service.player.playback?.is_playing == true }
        expect(!service.offline); expect(service.error == nil)
    }

    func testPlaybackHintsRespectRetryAfterWithoutUserRefresh() async throws {
        await StubNetwork.shared.reset(playbackResponses: [.init(status: 429, headers: ["Retry-After": "1"]), playingResponse])
        let (service, _, _) = fixture()
        let monitor = PlaybackMonitor(service: service, observeSystemEvents: false, pollInterval: .milliseconds(25))
        defer { monitor.stop(); service.disconnect() }
        monitor.start()
        try await waitUntil { service.recovery == .wait }
        for _ in 0..<100 { monitor.receiveDesktopEvent(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let before = await StubNetwork.shared.history()
        expect(before.filter { $0.url?.path == "/v1/me/player" }.count == 1)
        try await waitUntil { service.player.playback?.is_playing == true }
        expect(service.error == nil)
        let after = await StubNetwork.shared.history()
        expect(after.filter { $0.url?.path == "/v1/me/player" }.count == 2)
    }

    func testDisconnectPreventsDelayedPlaybackAndErrorsFromReturning() async throws {
        await StubNetwork.shared.reset(playbackResponses: [.init(delay: .milliseconds(100), failure: .timedOut)])
        let (service, _, _) = fixture()
        let request = Task { await service.refreshPlayback() }
        try await waitForPlaybackRequests(1)
        service.disconnect(); await request.value
        expect(service.player.playback == nil); expect(service.error == nil); expect(!service.connected)
        service.connected = true
        expect(service.playbackPollingDelay == .seconds(10))
        service.disconnect()
    }

    func testOptimisticControlsDoNotWaitForTheNetwork() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 204, delay: .milliseconds(250)) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        let start = ContinuousClock.now
        let operation = Task { await service.shuffle() }
        await Task.yield()
        expect(service.player.playback?.shuffle_state == true)
        expect(service.player.pendingCommands == 1)
        let feedbackTime = start.duration(to: .now)
        expect(feedbackTime < .milliseconds(100))
        print("Local control feedback: \(feedbackTime)")
        await operation.value
        expect(service.player.pendingCommands == 0)
    }

    func testRapidCommandsReachSpotifyInOrder() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 204, delay: .milliseconds(70)) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        let first = Task { await service.shuffle() }; await Task.yield()
        let second = Task { await service.shuffle() }; await Task.yield()
        let third = Task { await service.repeatMode() }; await Task.yield()
        expect(service.player.playback?.shuffle_state == false)
        expect(service.player.playback?.repeat_state == "context")
        await first.value; await second.value; await third.value
        let history = await StubNetwork.shared.history()
        expect(history.map { $0.url!.path } == ["/v1/me/player/shuffle", "/v1/me/player/shuffle", "/v1/me/player/repeat"])
        expect(history.compactMap { query($0, "state") } == ["true", "false", "context"])
    }

    func testAllPlayerControlsUseTheirExpectedSpotifyCommands() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 204) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        await service.next()
        await service.previous()
        await service.togglePlayback()
        await service.togglePlayback()
        await service.shuffle()
        await service.shuffle()
        await service.repeatMode()
        await service.repeatMode()
        await service.repeatMode()
        let history = await StubNetwork.shared.history()
        expect(history.map { "\($0.httpMethod ?? "") \($0.url!.path)" } == [
            "POST /v1/me/player/next", "POST /v1/me/player/previous",
            "PUT /v1/me/player/pause", "PUT /v1/me/player/play",
            "PUT /v1/me/player/shuffle", "PUT /v1/me/player/shuffle",
            "PUT /v1/me/player/repeat", "PUT /v1/me/player/repeat", "PUT /v1/me/player/repeat"
        ])
        expect(history.compactMap { query($0, "state") } == ["true", "false", "context", "track", "off"])
        expect(service.player.playback?.is_playing == true)
        expect(service.player.playback?.shuffle_state == false)
        expect(service.player.playback?.repeat_state == "off")
    }

    func testAmbiguousPlayerFailuresNeverRepeatNonIdempotentCommandsLocally() {
        expect(allowsDesktopFallback(after: APIError.noDevice))
        expect(allowsDesktopFallback(after: APIError.forbidden))
        expect(!allowsDesktopFallback(after: APIError.offline))
        expect(!allowsDesktopFallback(after: APIError.ambiguousResponse))
        expect(!allowsDesktopFallback(after: APIError.rateLimited(5)))
        expect(!allowsDesktopFallback(after: URLError(.timedOut)))
        expect(!allowsDesktopFallback(after: URLError(.networkConnectionLost)))
    }

    func testNextInvalidatesInFlightStalePausedPlayback() async throws {
        var delayedPaused = pausedResponse
        delayedPaused.delay = .milliseconds(120)
        let stalePaused = delayedPaused
        await StubNetwork.shared.reset { request in
            request.url?.path == "/v1/me/player" ? stalePaused : .init(status: 204)
        }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        let refresh = Task { await service.refreshPlayback() }
        try await waitForPlaybackRequests(1)
        await service.next()
        await refresh.value
        expect(service.player.playback?.is_playing == true)
        expect(service.player.playback?.item == song)
    }

    func testFailuresRollbackOnlyTheAffectedControl() async throws {
        await StubNetwork.shared.reset { request in .init(status: request.url!.path.hasSuffix("shuffle") ? 403 : 204, delay: .milliseconds(50)) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        let first = Task { await service.shuffle() }; await Task.yield()
        let second = Task { await service.repeatMode() }; await Task.yield()
        await first.value; await second.value
        expect(service.player.playback?.shuffle_state == false)
        expect(service.player.playback?.repeat_state == "context")
    }

    func testTwoFailedTogglesRestoreTheConfirmedState() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 403, delay: .milliseconds(50)) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        let first = Task { await service.shuffle() }; await Task.yield()
        let second = Task { await service.shuffle() }; await Task.yield()
        await first.value; await second.value
        expect(service.player.playback?.shuffle_state == false)
        expect(service.player.pendingCommands == 0)
    }

    func testHeartsUseCurrentEndpointAndSupportUndo() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 200, delay: .milliseconds(60)) }
        let (service, _, _) = fixture()
        let save = Task { await service.setSaved(song, to: true) }; await Task.yield()
        expect(service.player.isSaved(song)); expect(service.saved.count == 1)
        await save.value
        let history = await StubNetwork.shared.history()
        expect(history.first?.url?.path == "/v1/me/library")
        expect(history.first?.httpMethod == "PUT")
        expect(history.first.map { query($0, "uris") } == song.uri)
        service.notice?.undo?()
        try await waitUntil { !service.player.isSaved(song) }
        try await waitUntil { service.player.pendingCommands == 0 }
        let after = await StubNetwork.shared.history()
        expect(after.last?.httpMethod == "DELETE")
        expect(service.saved.isEmpty)
    }

    func testFailedSaveDoesNotEraseAnotherConcurrentSave() async throws {
        await StubNetwork.shared.reset { request in
            let uri = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            return .init(status: uri?.hasSuffix(":one") == true ? 403 : 200, delay: .milliseconds(60))
        }
        let (service, _, _) = fixture()
        let other = Track(id: "two", name: "Second song", uri: "spotify:track:two", duration_ms: nil, artists: nil, album: nil)
        let first = Task { await service.setSaved(song, to: true) }; await Task.yield()
        let second = Task { await service.setSaved(other, to: true) }; await Task.yield()
        await first.value; await second.value
        expect(!service.player.isSaved(song)); expect(service.player.isSaved(other))
        expect(service.saved.map(\.stableID) == ["two"])
    }

    func testRapidHeartClicksAreNotDropped() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 200, delay: .milliseconds(60)) }
        let (service, _, _) = fixture()
        let first = Task { await service.setSaved(song, to: true) }; await Task.yield()
        let second = Task { await service.setSaved(song, to: false) }; await Task.yield()
        expect(!service.player.isSaved(song))
        await first.value; await second.value
        let history = await StubNetwork.shared.history()
        expect(history.map(\.httpMethod) == ["PUT", "DELETE"])
        expect(service.saved.isEmpty)
    }

    func testPaginationDeduplicatesWithoutDroppingTracksWithMissingIDs() async throws {
        await StubNetwork.shared.reset { _ in .init(json: #"{"items":[{"track":{"id":"one","name":"First song","uri":"spotify:track:one"}},{"track":{"name":"Local A","uri":"spotify:local:a"}},{"track":{"name":"Local B","uri":"spotify:local:b"}}],"next":null}"#) }
        let (service, _, _) = fixture(); service.saved = [song]; service.savedNext = "https://api.spotify.com/v1/me/tracks?offset=30"
        await service.loadMoreSaved()
        expect(service.saved.map(\.name) == ["First song", "Local A", "Local B"])
        expect(service.savedNext == nil); expect(service.player.savedIDs.count == 3)
    }

    func testSearchDebouncesAndNeverPublishesStaleResults() async throws {
        await StubNetwork.shared.reset { request in
            let text = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            return .init(json: "{\"tracks\":{\"items\":[{\"id\":\"\(text)\",\"name\":\"\(text)\"}]}}", delay: text == "older" ? .milliseconds(400) : .milliseconds(20))
        }
        let (service, _, _) = fixture()
        service.searchFor("o"); service.searchFor("ol"); service.searchFor("older")
        try await Task.sleep(for: .milliseconds(270))
        service.searchFor("latest")
        try await waitUntil { service.search?.tracks?.items.first?.name == "latest" }
        try await Task.sleep(for: .milliseconds(220))
        expect(service.search?.tracks?.items.first?.name == "latest")
        let history = await StubNetwork.shared.history()
        expect(history.map { query($0, "q") } == ["older", "latest"])
        service.searchFor(""); expect(service.search == nil); expect(!service.searching)
    }

    func testStaleRequestsCannotRestoreDataAfterDisconnect() async throws {
        await StubNetwork.shared.reset { _ in .init(json: #"{"queue":[{"id":"one","name":"First song"}]}"#, delay: .milliseconds(70)) }
        let (service, _, _) = fixture()
        let task = Task { await service.loadQueue() }; await Task.yield()
        service.disconnect(); await task.value
        expect(service.queue.isEmpty); expect(service.error == nil); expect(!service.connected)
    }

    func testRateLimitsDoNotFloodSpotify() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 429, headers: ["Retry-After": "5"]) }
        let (service, _, _) = fixture(); service.player.apply(playback(song))
        await service.shuffle(); await service.repeatMode()
        let history = await StubNetwork.shared.history()
        expect(history.count == 1); expect(service.recovery == .wait)
        expect(service.player.playback?.shuffle_state == false); expect(service.player.playback?.repeat_state == "off")
    }

    func testOfflineErrorsKeepCachedContentAvailable() async {
        await StubNetwork.shared.reset { _ in .init(failure: .notConnectedToInternet) }
        let (service, _, _) = fixture(); service.saved = [song]
        await service.loadDevices()
        expect(service.offline); expect(service.recovery == .retry); expect(service.saved == [song])
    }

    func testDeviceTransferShowsProgressAndRefreshesDevices() async {
        await StubNetwork.shared.reset { request in
            if request.httpMethod == "PUT" { return .init(status: 204, delay: .milliseconds(70)) }
            return .init(json: #"{"devices":[{"id":"phone","name":"My phone","type":"Smartphone","is_active":true}]}"#)
        }
        let (service, _, _) = fixture()
        let device = Device(id: "phone", name: "My phone", type: "Smartphone", is_active: false, volume_percent: nil, supports_volume: false, is_restricted: false)
        let transfer = Task { await service.transfer(to: device) }; await Task.yield()
        expect(service.player.transferringID == "phone")
        await transfer.value
        expect(service.player.transferringID == nil); expect(service.devices.first?.is_active == true)
        expect(service.notice?.message == "Connected to My phone")
    }

    func testSavedCheckCannotOverwriteANewerHeartClick() async throws {
        await StubNetwork.shared.reset { request in
            if request.url!.path.hasSuffix("contains") { return .init(json: "[false]", delay: .milliseconds(150)) }
            return .init(status: 200, delay: .milliseconds(20))
        }
        let (service, _, _) = fixture()
        let check = Task { await service.checkSaved([song]) }
        try await Task.sleep(for: .milliseconds(20))
        await service.setSaved(song, to: true); await check.value
        expect(service.player.isSaved(song))
    }

    func testCollectionPlaybackUsesItsContext() async throws {
        await StubNetwork.shared.reset { request in
            if request.httpMethod == "GET" { return .init(json: #"{"items":[{"item":{"id":"one","name":"First song","uri":"spotify:track:one"}}]}"#) }
            return .init(status: 204)
        }
        let (service, _, _) = fixture()
        let playlist = Playlist(id: "mix", name: "My mix", uri: "spotify:playlist:mix", description: nil, images: nil)
        await service.openPlaylist(playlist); await service.playCollection()
        let history = await StubNetwork.shared.history()
        let command = try require(history.first { $0.httpMethod == "PUT" })
        var bodyData = command.httpBody
        if bodyData == nil, let stream = command.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096), data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(buffer, count: count)
            }
            bodyData = data
        }
        let body = try require(bodyData)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        expect(object?["context_uri"] as? String == "spotify:playlist:mix")
    }

    private func tone(_ frequency: Double, amplitude: Float = 0.2) -> [Float] {
        (0..<SpectrumAnalyzer.sampleCount).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / 48000)) }
    }
    func testLiveSpectrumMeasuresFrequencyAndLoudness() {
        let low = SpectrumAnalyzer().analyze(tone(93.75), sampleRate: 48000, at: 1)
        let high = SpectrumAnalyzer().analyze(tone(6000), sampleRate: 48000, at: 1)
        let lowPeak = low.bands.firstIndex(of: low.bands.max()!)!
        let highPeak = high.bands.firstIndex(of: high.bands.max()!)!
        expect(lowPeak < 8 && highPeak > 16)
        expect(abs(low.energy - 0.141421) < 0.005)
        expect(low.waveform.count == 64 && low.waveform.contains { abs($0) > 0.19 })
        expect(low.bands.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
    }
    func testSilenceAndInvalidAudioNeverFabricateBeats() {
        let analyzer = SpectrumAnalyzer()
        let silence = analyzer.analyze(Array(repeating: 0, count: 2048), sampleRate: 48000, at: 1)
        expect(silence.energy == 0 && silence.beat == 0 && silence.bands.allSatisfy { $0 == 0 })
        let invalid = analyzer.analyze(Array(repeating: .nan, count: 2048), sampleRate: 48000, at: 2)
        expect(invalid.energy == 0 && invalid.waveform.allSatisfy { $0 == 0 })
        expect(analyzer.analyze([0], sampleRate: 48000, at: 2) == .zero)
        expect(analyzer.analyze(tone(93.75), sampleRate: 0, at: 2) == .zero)
        expect(!silence.isFresh(at: 2) && silence.isFresh(at: 1.1))
    }
    func testBassOnsetPulsesDecayWithoutInventingATempo() {
        let analyzer = SpectrumAnalyzer()
        let onset = analyzer.analyze(tone(93.75), sampleRate: 48000, at: 1)
        expect(onset.beat == 1)
        var frame = onset
        for index in 1...12 { frame = analyzer.analyze(tone(93.75), sampleRate: 48000, at: 1 + Double(index) / 24) }
        expect(frame.beat < 0.05)
        for index in 1...40 { frame = analyzer.analyze(Array(repeating: 0, count: 2048), sampleRate: 48000, at: 2 + Double(index) / 24) }
        expect(frame.energy == 0 && frame.beat < 0.001 && (frame.bands.max() ?? 0) < 0.001)
    }
    func testAudioCaptureIsOptInAndStopsForHiddenOrRemotePlayback() async throws {
        let mock = MockAudioCapture()
        let measured = AudioVisualizer(capture: mock)
        measured.update(enabled: false, active: true, remote: false, track: "test")
        await measured.settle(); expect(measured.status == .off)
        measured.update(enabled: true, active: true, remote: true, track: "test")
        await measured.settle(); expect(measured.status == .remote)
        let beforeCapture = await mock.counts()
        expect(beforeCapture.0 == 0)
        measured.update(enabled: true, active: true, remote: false, track: "test")
        await measured.settle(); expect(measured.status == .listening)
        let frame = SpectrumAnalyzer().analyze(tone(93.75), sampleRate: 48000, at: Date.timeIntervalSinceReferenceDate)
        await mock.emit(frame)
        try await waitUntil { measured.frame == frame }
        measured.update(enabled: true, active: false, remote: false, track: "test")
        await measured.settle(); expect(measured.status == .suspended && measured.frame == .zero)
        await mock.emit(frame)
        try await Task.sleep(for: .milliseconds(30))
        expect(measured.frame == .zero)
        let afterCapture = await mock.counts()
        expect(afterCapture.1 >= 3)
    }
    func testCancelledCaptureAndUnavailableAudioDoNotRestartAutomatically() async {
        let mock = MockAudioCapture(), visualizer = AudioVisualizer(capture: mock)
        visualizer.update(enabled: true, active: true, remote: false, track: "test")
        visualizer.shutdown()
        await visualizer.settle()
        expect(visualizer.status == .off && visualizer.frame == .zero)
        await mock.setFailure()
        visualizer.update(enabled: true, active: true, remote: false, track: "test")
        await visualizer.settle()
        if case .unavailable = visualizer.status {} else { expect(false) }
        let count = await mock.counts().0
        visualizer.update(enabled: true, active: true, remote: false, track: "test")
        await visualizer.settle()
        let afterRetry = await mock.counts()
        expect(afterRetry.0 == count)
        let error = visualizer.lastError
        expect(error != nil)
        // Settings suspends capture, but must retain the error and retry affordance.
        visualizer.update(enabled: true, active: false, remote: false, track: "test")
        await visualizer.settle()
        expect(visualizer.status == .suspended && visualizer.lastError == error)
        await mock.setFailure(false)
        visualizer.update(enabled: true, active: true, remote: false, track: "test")
        await visualizer.settle()
        expect(visualizer.status == .listening && visualizer.lastError == nil)
        visualizer.shutdown(); await visualizer.settle()
        expect(visualizer.lastError == nil)
    }
    func testVisualizerPreferencesPersistWithSafeDefaults() {
        let (_, defaults, _) = fixture()
        let preferences = AppPreferences(defaults: defaults)
        expect(!preferences.liveVisualizer)
        preferences.liveVisualizer = true
        let restored = AppPreferences(defaults: defaults)
        expect(restored.liveVisualizer)
        // Older style/intensity values no longer affect the single waveform experience.
        defaults.set("Spectrum", forKey: "visualizerStyle")
        defaults.set(Double.infinity, forKey: "visualizerIntensity")
        expect(AppPreferences(defaults: defaults).liveVisualizer)
    }

    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSearchPlaybackRetainsAlbumAndSelectedSong() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 204) }
        let (service, _, _) = fixture()
        let album = Album(id: "album", name: "Album", uri: nil, images: nil, artists: nil)
        let track = Track(id: "second", name: "Second song", uri: "spotify:track:second", duration_ms: nil, artists: nil, album: album)
        await service.activate(.track(track))
        let history = await StubNetwork.shared.history()
        let object = try requestObject(require(history.first))
        expect(object["context_uri"] as? String == "spotify:album:album")
        expect((object["offset"] as? [String: String])?["uri"] == track.uri)
        expect(object["uris"] == nil)
        expect(service.player.playback?.item == track)
        service.preferences.continuousPlayback = false
        await service.play(track)
        let commands = await StubNetwork.shared.history()
        let single = try requestObject(require(commands.last))
        expect(single["uris"] as? [String] == ["spotify:track:second"])
        expect(single["context_uri"] == nil)
    }

    func testLikedSongPlaybackUsesMarketRelinkedTrackURI() async throws {
        let playing = #"{"is_playing":true,"item":{"id":"playable","name":"First song","uri":"spotify:track:playable"}}"#
        await StubNetwork.shared.reset { request in
            if request.url?.path == "/v1/tracks/one" { return .init(json: #"{"uri":"spotify:track:playable","is_playable":true}"#) }
            if request.url?.path == "/v1/me/player" { return .init(json: playing) }
            return .init(status: 204)
        }
        let (service, _, _) = fixture(); service.saved = [song]
        await service.playLikedSong(song)
        let history = await StubNetwork.shared.history()
        let metadata = history.first { $0.url?.path == "/v1/tracks/one" }
        let play = history.first { $0.url?.path == "/v1/me/player/play" }
        let market = query(try require(metadata), "market")
        let uris = try requestObject(require(play))["uris"] as? [String]
        expect(market == "from_token")
        expect(uris == ["spotify:track:playable"])
        expect(service.notice == nil)
    }

    func testLikedSongPlaybackDoesNotStartAnUnavailableTrack() async throws {
        await StubNetwork.shared.reset { request in
            if request.url?.path == "/v1/tracks/one" { return .init(json: #"{"uri":"spotify:track:one","is_playable":false}"#) }
            return .init(status: 204)
        }
        let (service, _, _) = fixture(); service.saved = [song]
        await service.playLikedSong(song)
        let history = await StubNetwork.shared.history()
        expect(!history.contains { $0.url?.path == "/v1/me/player/play" })
        expect(service.notice?.message.contains("isn’t available") == true)
    }

    func testLikedSongVerifiesSingleTrackWhenShuffleCannotBeDisabled() async throws {
        let other = #"{"is_playing":true,"item":{"id":"other","name":"Other song","uri":"spotify:track:other"}}"#
        await StubNetwork.shared.reset { request in
            if request.url?.path == "/v1/me/player/shuffle" { return .init(status: 403) }
            if request.url?.path == "/v1/me/player" { return .init(json: other) }
            return .init(status: 204)
        }
        let (service, _, _) = fixture(); service.saved = [song]
        service.player.apply(Playback(is_playing: true, progress_ms: 0, repeat_state: "off", shuffle_state: true, item: song, device: nil))
        await service.playLikedSong(song)
        let history = await StubNetwork.shared.history()
        let play = history.first { $0.url?.path == "/v1/me/player/play" }
        let uris = try requestObject(require(play))["uris"] as? [String]
        expect(uris == ["spotify:track:one"])
        expect(service.notice?.message.contains("couldn’t start") == true)
    }

    func testQueueAndPlaylistSelectionKeepTheirOrder() async throws {
        await StubNetwork.shared.reset { _ in .init(status: 204) }
        let (service, _, _) = fixture()
        let next = Track(id: "next", name: "Next", uri: "spotify:track:next", duration_ms: nil, artists: nil, album: nil)
        await service.play(song, following: [next, song])
        var history = await StubNetwork.shared.history()
        let queue = try requestObject(require(history.first))
        expect(queue["uris"] as? [String] == ["spotify:track:one", "spotify:track:next", "spotify:track:one"])
        service.preferences.continuousPlayback = false
        await service.play(song, contextURI: "spotify:playlist:mix", contextPosition: 7)
        history = await StubNetwork.shared.history()
        let playlist = try requestObject(require(history.last))
        expect(playlist["context_uri"] as? String == "spotify:playlist:mix")
        expect((playlist["offset"] as? [String: Int])?["position"] == 7)
    }

    func testSettingsPersistAndSearchHistoryCanBeDisabled() {
        let (_, defaults, _) = fixture()
        let prefs = AppPreferences(defaults: defaults)
        expect(prefs.appearance == .auto && prefs.animations && prefs.continuousPlayback && prefs.desktopFallback && prefs.rememberSearches && prefs.playingIcon)
        prefs.appearance = .dark; prefs.animations = false; prefs.continuousPlayback = false
        prefs.desktopFallback = false; prefs.playingIcon = false
        prefs.rememberSearch("Private query"); prefs.rememberSearches = false
        prefs.rememberSearch("Another query")
        let restored = AppPreferences(defaults: defaults)
        expect(restored.appearance == .dark && !restored.animations && !restored.continuousPlayback)
        expect(!restored.desktopFallback && !restored.rememberSearches && !restored.playingIcon)
        expect(restored.recentSearches.isEmpty)
    }

    func testAppearanceOverridesAndReturnsToAuto() async throws {
        _ = NSApplication.shared
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let (service, _, _) = fixture()
        let popover = NSPopover(), preferences = service.preferences
        let appearance = SystemAppearance(popovers: [popover], preferences: preferences)
        defer { withExtendedLifetime(appearance) {} }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        preferences.appearance = .light
        try await waitUntil { popover.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua }
        NSApp.appearance = NSAppearance(named: .aqua)
        preferences.appearance = .dark
        try await waitUntil { popover.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
        preferences.appearance = .auto
        try await waitUntil { popover.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await waitUntil { popover.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    }

    func testDisabledDesktopFallbackReportsAPIError() async {
        await StubNetwork.shared.reset { _ in .init(status: 404) }
        let (service, _, _) = fixture()
        service.preferences.desktopFallback = false
        await service.next()
        expect(service.error != nil)
        expect(service.recovery == .device)
    }

    func testNativeViewsKeepCompactAndExpandedDimensions() async throws {
        _ = NSApplication.shared
        let mock = MockAudioCapture()
        let (service, defaults, _) = fixture(capture: mock)
        let preferences = AppPreferences(defaults: defaults)
        service.profile = Profile(display_name: "Aakash", product: "premium")
        service.player.apply(playback(song))
        service.saved = [song]; service.recent = [song, song]
        service.playlists = (0..<5).map { Playlist(id: "playlist\($0)", name: "Favorite playlist \($0)", uri: nil, description: nil, images: nil) }
        preferences.isPresented = true
        for scheme in [ColorScheme.light, .dark] {
        for screen in ["compact", "expanded", "library", "search", "devices", "settings", "live-waveform", "paused-waveform"] {
            let mode: PopoverMode = screen == "compact" ? .compact : .expanded
            preferences.compact = mode == .compact
            preferences.tab = screen == "library" ? .library : screen == "search" ? .search : .home
            preferences.showingDevices = screen == "devices"
            preferences.showingSettings = screen == "settings"
            if screen == "library" { service.saved = [song, Track(id: "long", name: "An exceptionally long song title to verify row truncation", uri: nil, duration_ms: nil, artists: [Artist(id: nil, name: "Artist name that should truncate safely without squeezing the actions", uri: nil)], album: nil)] }
            if screen == "search" {
                preferences.query = "Favorite"
                service.search = SearchResults(tracks: Page(items: [song], next: nil, total: 1), artists: nil, albums: nil, playlists: Page(items: service.playlists.map(Optional.some), next: nil, total: 5))
            }
            if screen == "devices" { service.devices = (0..<12).map { Device(id: "device\($0)", name: "Speaker \($0)", type: "Speaker", is_active: $0 == 0, volume_percent: 50, supports_volume: true, is_restricted: false) } }
            let liveFixture = screen.hasPrefix("live-")
            service.player.apply(playback(song, playing: screen != "paused-waveform", progress: 155000))
            if liveFixture {
                service.visualizer.update(enabled: true, active: true, remote: false, track: "synthetic-fixture")
                await service.visualizer.settle()
                let input = zip(tone(93.75), tone(3000, amplitude: 0.1)).map(+)
                let frame = SpectrumAnalyzer().analyze(input, sampleRate: 48000, at: Date.timeIntervalSinceReferenceDate)
                let count = await mock.counts().0
                await mock.emit(frame, callback: count - 1)
                try await waitUntil { service.visualizer.frame == frame }
            }
            let root = ContentView(mode: mode).environmentObject(service).environmentObject(service.player).environmentObject(preferences)
                .environment(\.colorScheme, scheme).environment(\.motionReduced, !liveFixture)
            let host = NSHostingController(rootView: root)
            host.sizingOptions = []
            let size = PopoverLayout.size(mode)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.isReleasedWhenClosed = false
            window.contentViewController = host
            host.view.frame = NSRect(origin: .zero, size: size)
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            expect(abs(host.view.bounds.width - size.width) < 1)
            expect(abs(host.view.bounds.height - size.height) < 1)
            let bitmap = try require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            let png = try require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("playmenu-\(scheme == .dark ? "dark" : "light")-\(screen).png"))
            window.close()
            service.visualizer.shutdown(); await service.visualizer.settle()
        }
        }

    }

    func testAnimationLoopsStopWhenHiddenPausedOrReduced() {
        let frame = SpectrumAnalyzer().analyze(tone(93.75), sampleRate: 48000, at: 1)
        for layer in 0..<3 {
            for amplitude in [0.62, Double(frame.energy)] {
                let levels = ProgressWaveMath.levels(at: 123456789, active: true, amplitude: amplitude, layer: layer)
                expect(levels.count == 80 && levels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
                expect(levels.first == 0 && abs(levels.last ?? 0) < 0.000001)
                expect(ProgressWaveMath.levels(at: 1, active: false, amplitude: amplitude, layer: layer).allSatisfy { $0 == 0 })
            }
        }
        var envelope = WaveEnvelope()
        envelope.retarget(to: 0.95, at: 1)
        expect(abs(envelope.value(at: 1) - 0.62) < 0.000001)
        expect(envelope.value(at: 1 + 1.0 / 60) - 0.62 < 0.02)
        // Fast audio fluctuations must not cause large per-frame surface jumps.
        envelope = WaveEnvelope()
        var previous = ProgressWaveMath.levels(at: 3599, active: true, amplitude: 0.62, layer: 0)
        for index in 0..<180 {
            let time = 3599 + Double(index) / 60
            envelope.retarget(to: index.isMultiple(of: 2) ? 0.3 : 0.95, at: time)
            let next = ProgressWaveMath.levels(at: time, active: true, amplitude: envelope.value(at: time), layer: 0)
            expect(zip(previous, next).allSatisfy { abs($0 - $1) < 0.04 })
            previous = next
        }
        let beforeInvalid = envelope.value(at: 3602)
        envelope.retarget(to: .infinity, at: 3602)
        expect(envelope.value(at: 3602) == beforeInvalid)
        expect(ProgressWaveMath.levels(at: .nan, active: true, amplitude: 0.6, layer: 0).allSatisfy { $0 == 0 })
        expect(Motion.runs(playing: true, presented: true, reduced: false))
        for playing in [true, false] {
            for visible in [true, false] {
                for reduced in [true, false] {
                    expect(Motion.runs(playing: playing, presented: visible, reduced: reduced) == (playing && visible && !reduced))
                }
            }
        }
        let initial = Motion.bars(at: 0, playing: true)
        expect(initial != Motion.bars(at: 0.2, playing: true))
        for index in 0..<300 {
            let values = Motion.bars(at: Double(index) / 30, playing: true)
            expect(values.count == 5); expect(values.allSatisfy { $0.isFinite && $0 >= 0.18 && $0 <= 1 })
        }
        expect(Motion.bars(at: 0, playing: false) == Motion.bars(at: 100, playing: false))
    }

    func testSystemAppearanceColorsAndContrast() throws {
        var backgrounds: [Double] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try require(NSAppearance(named: name))
            var capturedError: Error?
            appearance.performAsCurrentDrawingAppearance {
                do {
                func luminance(_ color: Color) throws -> Double {
                    let rgb = try require(NSColor(color).usingColorSpace(.sRGB))
                    func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
                    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
                }
                func contrast(_ first: Color, _ second: Color) throws -> Double {
                    let a = try luminance(first), b = try luminance(second)
                    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
                }
                backgrounds.append(try luminance(Palette.ink))
                let primaryContrast = try contrast(Palette.primary, Palette.ink)
                let accentContrast = try contrast(Palette.green, Palette.surface)
                let buttonContrast = try contrast(Palette.onAccent, Palette.green)
                expect(primaryContrast > 4.5); expect(accentContrast > 4.5); expect(buttonContrast > 4.5)
                } catch { capturedError = error }
            }
            if let capturedError { throw capturedError }
        }
        expect(backgrounds[0] > 0.8); expect(backgrounds[1] < 0.02)
    }

    func testMusicScrubbersClampDragAndKeyboardValues() {
        let volume = 0.0...100.0, song = 0.0...240000.0
        expect(ScrubberMath.value(at: -20, width: 100, range: volume) == 0)
        expect(ScrubberMath.value(at: 150, width: 100, range: volume) == 100)
        expect(ScrubberMath.value(at: 50, width: 100, range: song) == 120000)
        expect(ScrubberMath.value(at: 0, width: 0, range: song).isFinite)
        expect(ScrubberMath.fraction(-10, range: volume) == 0)
        expect(ScrubberMath.fraction(200, range: volume) == 1)
        expect(ScrubberMath.fraction(120000, range: song) == 0.5)
    }

    func testPopoverAppearanceFollowsSystemChangesWithoutResizing() async throws {
        _ = NSApplication.shared
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let compact = NSPopover(), expanded = NSPopover()
        compact.contentSize = PopoverLayout.size(.compact); expanded.contentSize = PopoverLayout.size(.expanded)
        let appearance = SystemAppearance(popovers: [compact, expanded])
        defer { withExtendedLifetime(appearance) {} }
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSApp.appearance = try require(NSAppearance(named: name))
            try await waitUntil { compact.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name && expanded.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name }
            expect(compact.contentSize == PopoverLayout.size(.compact))
            expect(expanded.contentSize == PopoverLayout.size(.expanded))
        }
    }

    func testPreferencesSurviveRelaunch() {
        let (_, defaults, _) = fixture()
        let preferences = AppPreferences(defaults: defaults)
        preferences.compact = true; preferences.tab = .library; preferences.filter = .pinned
        let playlist = Playlist(id: "favorite", name: "Favorite", uri: nil, description: nil, images: nil)
        preferences.togglePin(playlist); preferences.scrollAnchors["Library"] = "library:playlist:favorite"
        for index in 0..<10 { preferences.rememberSearch("Query \(index)") }
        preferences.rememberSearch(" query 9 ")
        let restored = AppPreferences(defaults: defaults)
        expect(restored.compact); expect(restored.tab == .library); expect(restored.filter == .pinned)
        expect(restored.pinnedIDs == ["favorite"]); expect(restored.recentSearches.count == 8)
        expect(restored.recentSearches.first == "query 9")
        expect(restored.scrollAnchors["Library"] == "library:playlist:favorite")
        let player = PlayerState(defaults: defaults); player.setVolume(72)
        expect(PlayerState(defaults: defaults).volume == 72)
    }

    func testSnapshotRestoresContentAndRejectsAnotherClient() async {
        let (_, _, directory) = fixture(); let cache = LibraryCache(directory: directory)
        let snapshot = LibrarySnapshot(clientID: "first", profile: Profile(display_name: "Name", product: nil), playlists: [], saved: [song], recent: [song], topTracks: [], playlistNext: nil, savedNext: "next", savedIDs: ["one"], date: Date())
        await cache.save(snapshot)
        let restored = await cache.load(clientID: "first")
        expect(restored?.saved == [song]); expect(restored?.savedNext == "next")
        let wrongAccount = await cache.load(clientID: "other"); expect(wrongAccount == nil)
        await cache.clear(); let cleared = await cache.load(clientID: "first"); expect(cleared == nil)
    }

    func testOldAndNewPlaylistItemsDecode() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(PlaylistItem.self, from: Data(#"{"track":{"id":"one","name":"First song"}}"#.utf8))
        let current = try decoder.decode(PlaylistItem.self, from: Data(#"{"item":{"id":"two","name":"Second song"}}"#.utf8))
        let removed = try decoder.decode(PlaylistItem.self, from: Data(#"{"item":null}"#.utf8))
        expect(old.resolved?.id == "one"); expect(current.resolved?.id == "two"); expect(removed.resolved == nil)
    }

    func testThumbnailsAreDownsampledToTheirDisplaySize() throws {
        let image = NSImage(size: NSSize(width: 1400, height: 1400))
        image.lockFocus(); NSColor.green.setFill(); NSRect(x: 0, y: 0, width: 1400, height: 1400).fill(); image.unlockFocus()
        let data = try require(image.tiffRepresentation)
        let thumbnail = try require(downsample(data, pixels: 84))
        let source = try require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let result = try require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        expect(result.width == 84); expect(result.height == 84)
        expect(artworkKey(URL(string: "https://example.com/cover")!, 84) != artworkKey(URL(string: "https://example.com/cover")!, 220))
    }

    func testRapidModeSwitchesAndDismissalsInvalidateOldReopens() {
        var state = PresentationState()
        for _ in 0..<100 {
            let compact = state.request(.compact), expanded = state.request(.expanded)
            expect(!state.accepts(compact, mode: .compact)); expect(state.accepts(expanded, mode: .expanded))
            state.dismiss(); expect(!state.accepts(expanded, mode: .expanded))
        }
    }
}

@MainActor private var failures: [String] = []
@MainActor private func expect(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value() { failures.append("\(file):\(line): expectation failed") }
}
private struct MissingValue: Error {}
private func require<T>(_ value: T?) throws -> T { guard let value else { throw MissingValue() }; return value }

@main struct PlayMenuChecks {
    @MainActor static func main() async {
        let checks = PlayMenuTests()
        var passed = 0
        do {
            let before = failures.count
            checks.testDesktopEventsUpdatePlaybackWithoutWaitingForTheAPI()
            if failures.count == before { passed += 1; print("PASS testDesktopEventsUpdatePlaybackWithoutWaitingForTheAPI") }
        }
        do {
            let before = failures.count
            try await checks.testDesktopEventsDoNotOverrideAnActiveRemoteDeviceOrCommand()
            if failures.count == before { passed += 1; print("PASS testDesktopEventsDoNotOverrideAnActiveRemoteDeviceOrCommand") }
        } catch { failures.append("testDesktopEventsDoNotOverrideAnActiveRemoteDeviceOrCommand: \(error)") }
        do {
            let before = failures.count
            try await checks.testDesktopEventsSurviveStaleAndEmptyAPIResponses()
            if failures.count == before { passed += 1; print("PASS testDesktopEventsSurviveStaleAndEmptyAPIResponses") }
        } catch { failures.append("testDesktopEventsSurviveStaleAndEmptyAPIResponses: \(error)") }
        do {
            let before = failures.count
            try await checks.testSlowSavedStatusDoesNotBlockPlaybackRefresh()
            if failures.count == before { passed += 1; print("PASS testSlowSavedStatusDoesNotBlockPlaybackRefresh") }
        } catch { failures.append("testSlowSavedStatusDoesNotBlockPlaybackRefresh: \(error)") }
        do {
            let before = failures.count
            try await checks.testBackgroundMonitorDetectsMusicWithTheMenuClosed()
            if failures.count == before { passed += 1; print("PASS testBackgroundMonitorDetectsMusicWithTheMenuClosed") }
        } catch { failures.append("testBackgroundMonitorDetectsMusicWithTheMenuClosed: \(error)") }
        do {
            let before = failures.count
            try await checks.testPlaybackHintsDuringAFetchQueueOneFollowUp()
            if failures.count == before { passed += 1; print("PASS testPlaybackHintsDuringAFetchQueueOneFollowUp") }
        } catch { failures.append("testPlaybackHintsDuringAFetchQueueOneFollowUp: \(error)") }
        do {
            let before = failures.count
            try await checks.testOpeningTheMenuWakesBackgroundPollingAndStopRemovesIt()
            if failures.count == before { passed += 1; print("PASS testOpeningTheMenuWakesBackgroundPollingAndStopRemovesIt") }
        } catch { failures.append("testOpeningTheMenuWakesBackgroundPollingAndStopRemovesIt: \(error)") }
        do {
            let before = failures.count
            try await checks.testPlaybackMonitorRecoversFromNetworkFailureAutomatically()
            if failures.count == before { passed += 1; print("PASS testPlaybackMonitorRecoversFromNetworkFailureAutomatically") }
        } catch { failures.append("testPlaybackMonitorRecoversFromNetworkFailureAutomatically: \(error)") }
        do {
            let before = failures.count
            try await checks.testPlaybackHintsRespectRetryAfterWithoutUserRefresh()
            if failures.count == before { passed += 1; print("PASS testPlaybackHintsRespectRetryAfterWithoutUserRefresh") }
        } catch { failures.append("testPlaybackHintsRespectRetryAfterWithoutUserRefresh: \(error)") }
        do {
            let before = failures.count
            try await checks.testDisconnectPreventsDelayedPlaybackAndErrorsFromReturning()
            if failures.count == before { passed += 1; print("PASS testDisconnectPreventsDelayedPlaybackAndErrorsFromReturning") }
        } catch { failures.append("testDisconnectPreventsDelayedPlaybackAndErrorsFromReturning: \(error)") }
        do {
            let before = failures.count
            checks.testLiveSpectrumMeasuresFrequencyAndLoudness()
            if failures.count == before { passed += 1; print("PASS testLiveSpectrumMeasuresFrequencyAndLoudness") }
        }
        do {
            let before = failures.count
            checks.testSilenceAndInvalidAudioNeverFabricateBeats()
            if failures.count == before { passed += 1; print("PASS testSilenceAndInvalidAudioNeverFabricateBeats") }
        }
        do {
            let before = failures.count
            checks.testBassOnsetPulsesDecayWithoutInventingATempo()
            if failures.count == before { passed += 1; print("PASS testBassOnsetPulsesDecayWithoutInventingATempo") }
        }
        do {
            let before = failures.count
            try await checks.testAudioCaptureIsOptInAndStopsForHiddenOrRemotePlayback()
            if failures.count == before { passed += 1; print("PASS testAudioCaptureIsOptInAndStopsForHiddenOrRemotePlayback") }
        } catch { failures.append("testAudioCaptureIsOptInAndStopsForHiddenOrRemotePlayback: \(error)") }
        do {
            let before = failures.count
            await checks.testCancelledCaptureAndUnavailableAudioDoNotRestartAutomatically()
            if failures.count == before { passed += 1; print("PASS testCancelledCaptureAndUnavailableAudioDoNotRestartAutomatically") }
        }
        do {
            let before = failures.count
            checks.testVisualizerPreferencesPersistWithSafeDefaults()
            if failures.count == before { passed += 1; print("PASS testVisualizerPreferencesPersistWithSafeDefaults") }
        }
        do {
            let before = failures.count
            try await checks.testSearchPlaybackRetainsAlbumAndSelectedSong()
            if failures.count == before { passed += 1; print("PASS testSearchPlaybackRetainsAlbumAndSelectedSong") }
        } catch { failures.append("testSearchPlaybackRetainsAlbumAndSelectedSong: \(error)") }
        do {
            let before = failures.count
            try await checks.testLikedSongPlaybackUsesMarketRelinkedTrackURI()
            if failures.count == before { passed += 1; print("PASS testLikedSongPlaybackUsesMarketRelinkedTrackURI") }
        } catch { failures.append("testLikedSongPlaybackUsesMarketRelinkedTrackURI: \(error)") }
        do {
            let before = failures.count
            try await checks.testLikedSongPlaybackDoesNotStartAnUnavailableTrack()
            if failures.count == before { passed += 1; print("PASS testLikedSongPlaybackDoesNotStartAnUnavailableTrack") }
        } catch { failures.append("testLikedSongPlaybackDoesNotStartAnUnavailableTrack: \(error)") }
        do {
            let before = failures.count
            try await checks.testLikedSongVerifiesSingleTrackWhenShuffleCannotBeDisabled()
            if failures.count == before { passed += 1; print("PASS testLikedSongVerifiesSingleTrackWhenShuffleCannotBeDisabled") }
        } catch { failures.append("testLikedSongVerifiesSingleTrackWhenShuffleCannotBeDisabled: \(error)") }
        do {
            let before = failures.count
            try await checks.testQueueAndPlaylistSelectionKeepTheirOrder()
            if failures.count == before { passed += 1; print("PASS testQueueAndPlaylistSelectionKeepTheirOrder") }
        } catch { failures.append("testQueueAndPlaylistSelectionKeepTheirOrder: \(error)") }
        do {
            let before = failures.count
            checks.testSettingsPersistAndSearchHistoryCanBeDisabled()
            if failures.count == before { passed += 1; print("PASS testSettingsPersistAndSearchHistoryCanBeDisabled") }
        }
        do {
            let before = failures.count
            try await checks.testAppearanceOverridesAndReturnsToAuto()
            if failures.count == before { passed += 1; print("PASS testAppearanceOverridesAndReturnsToAuto") }
        } catch { failures.append("testAppearanceOverridesAndReturnsToAuto: \(error)") }

        do {
            let before = failures.count
            await checks.testDisabledDesktopFallbackReportsAPIError()
            if failures.count == before { passed += 1; print("PASS testDisabledDesktopFallbackReportsAPIError") }
        }
        do {
            let before = failures.count
            try await checks.testOptimisticControlsDoNotWaitForTheNetwork()
            if failures.count == before { passed += 1; print("PASS testOptimisticControlsDoNotWaitForTheNetwork") }
        } catch { failures.append("testOptimisticControlsDoNotWaitForTheNetwork: \(error)") }
        do {
            let before = failures.count
            try await checks.testRapidCommandsReachSpotifyInOrder()
            if failures.count == before { passed += 1; print("PASS testRapidCommandsReachSpotifyInOrder") }
        } catch { failures.append("testRapidCommandsReachSpotifyInOrder: \(error)") }
        do {
            let before = failures.count
            try await checks.testAllPlayerControlsUseTheirExpectedSpotifyCommands()
            if failures.count == before { passed += 1; print("PASS testAllPlayerControlsUseTheirExpectedSpotifyCommands") }
        } catch { failures.append("testAllPlayerControlsUseTheirExpectedSpotifyCommands: \(error)") }
        do {
            let before = failures.count
            checks.testAmbiguousPlayerFailuresNeverRepeatNonIdempotentCommandsLocally()
            if failures.count == before { passed += 1; print("PASS testAmbiguousPlayerFailuresNeverRepeatNonIdempotentCommandsLocally") }
        }
        do {
            let before = failures.count
            try await checks.testNextInvalidatesInFlightStalePausedPlayback()
            if failures.count == before { passed += 1; print("PASS testNextInvalidatesInFlightStalePausedPlayback") }
        } catch { failures.append("testNextInvalidatesInFlightStalePausedPlayback: \(error)") }
        do {
            let before = failures.count
            try await checks.testFailuresRollbackOnlyTheAffectedControl()
            if failures.count == before { passed += 1; print("PASS testFailuresRollbackOnlyTheAffectedControl") }
        } catch { failures.append("testFailuresRollbackOnlyTheAffectedControl: \(error)") }
        do {
            let before = failures.count
            try await checks.testTwoFailedTogglesRestoreTheConfirmedState()
            if failures.count == before { passed += 1; print("PASS testTwoFailedTogglesRestoreTheConfirmedState") }
        } catch { failures.append("testTwoFailedTogglesRestoreTheConfirmedState: \(error)") }
        do {
            let before = failures.count
            try await checks.testHeartsUseCurrentEndpointAndSupportUndo()
            if failures.count == before { passed += 1; print("PASS testHeartsUseCurrentEndpointAndSupportUndo") }
        } catch { failures.append("testHeartsUseCurrentEndpointAndSupportUndo: \(error)") }
        do {
            let before = failures.count
            try await checks.testFailedSaveDoesNotEraseAnotherConcurrentSave()
            if failures.count == before { passed += 1; print("PASS testFailedSaveDoesNotEraseAnotherConcurrentSave") }
        } catch { failures.append("testFailedSaveDoesNotEraseAnotherConcurrentSave: \(error)") }
        do {
            let before = failures.count
            try await checks.testRapidHeartClicksAreNotDropped()
            if failures.count == before { passed += 1; print("PASS testRapidHeartClicksAreNotDropped") }
        } catch { failures.append("testRapidHeartClicksAreNotDropped: \(error)") }
        do {
            let before = failures.count
            try await checks.testPaginationDeduplicatesWithoutDroppingTracksWithMissingIDs()
            if failures.count == before { passed += 1; print("PASS testPaginationDeduplicatesWithoutDroppingTracksWithMissingIDs") }
        } catch { failures.append("testPaginationDeduplicatesWithoutDroppingTracksWithMissingIDs: \(error)") }
        do {
            let before = failures.count
            try await checks.testSearchDebouncesAndNeverPublishesStaleResults()
            if failures.count == before { passed += 1; print("PASS testSearchDebouncesAndNeverPublishesStaleResults") }
        } catch { failures.append("testSearchDebouncesAndNeverPublishesStaleResults: \(error)") }
        do {
            let before = failures.count
            try await checks.testStaleRequestsCannotRestoreDataAfterDisconnect()
            if failures.count == before { passed += 1; print("PASS testStaleRequestsCannotRestoreDataAfterDisconnect") }
        } catch { failures.append("testStaleRequestsCannotRestoreDataAfterDisconnect: \(error)") }
        do {
            let before = failures.count
            try await checks.testRateLimitsDoNotFloodSpotify()
            if failures.count == before { passed += 1; print("PASS testRateLimitsDoNotFloodSpotify") }
        } catch { failures.append("testRateLimitsDoNotFloodSpotify: \(error)") }
        do {
            let before = failures.count
            checks.testPreferencesSurviveRelaunch()
            if failures.count == before { passed += 1; print("PASS testPreferencesSurviveRelaunch") }
        }
        do {
            let before = failures.count
            await checks.testSnapshotRestoresContentAndRejectsAnotherClient()
            if failures.count == before { passed += 1; print("PASS testSnapshotRestoresContentAndRejectsAnotherClient") }
        }
        do {
            let before = failures.count
            try checks.testOldAndNewPlaylistItemsDecode()
            if failures.count == before { passed += 1; print("PASS testOldAndNewPlaylistItemsDecode") }
        } catch { failures.append("testOldAndNewPlaylistItemsDecode: \(error)") }
        do {
            let before = failures.count
            try checks.testThumbnailsAreDownsampledToTheirDisplaySize()
            if failures.count == before { passed += 1; print("PASS testThumbnailsAreDownsampledToTheirDisplaySize") }
        } catch { failures.append("testThumbnailsAreDownsampledToTheirDisplaySize: \(error)") }
        do {
            let before = failures.count
            checks.testRapidModeSwitchesAndDismissalsInvalidateOldReopens()
            if failures.count == before { passed += 1; print("PASS testRapidModeSwitchesAndDismissalsInvalidateOldReopens") }
        }
        do {
            let before = failures.count
            await checks.testOfflineErrorsKeepCachedContentAvailable()
            if failures.count == before { passed += 1; print("PASS testOfflineErrorsKeepCachedContentAvailable") }
        }
        do {
            let before = failures.count
            await checks.testDeviceTransferShowsProgressAndRefreshesDevices()
            if failures.count == before { passed += 1; print("PASS testDeviceTransferShowsProgressAndRefreshesDevices") }
        }
        do {
            let before = failures.count
            try await checks.testSavedCheckCannotOverwriteANewerHeartClick()
            if failures.count == before { passed += 1; print("PASS testSavedCheckCannotOverwriteANewerHeartClick") }
        } catch { failures.append("testSavedCheckCannotOverwriteANewerHeartClick: \(error)") }
        do {
            let before = failures.count
            try await checks.testCollectionPlaybackUsesItsContext()
            if failures.count == before { passed += 1; print("PASS testCollectionPlaybackUsesItsContext") }
        } catch { failures.append("testCollectionPlaybackUsesItsContext: \(error)") }
        let skipUIRender = (ProcessInfo.processInfo.environment["PLAYMENU_SKIP_UI_RENDER"] ?? ProcessInfo.processInfo.environment["SPOTMENU_SKIP_UI_RENDER"]) == "1"
        if skipUIRender {
            print("SKIP testNativeViewsKeepCompactAndExpandedDimensions: native GPU rendering explicitly disabled by PLAYMENU_SKIP_UI_RENDER; run on a Mac with working graphics")
        } else {
            do {
                let before = failures.count
                try await checks.testNativeViewsKeepCompactAndExpandedDimensions()
                if failures.count == before { passed += 1; print("PASS testNativeViewsKeepCompactAndExpandedDimensions") }
            } catch { failures.append("testNativeViewsKeepCompactAndExpandedDimensions: \(error)") }
        }
        do {
            let before = failures.count
            checks.testAnimationLoopsStopWhenHiddenPausedOrReduced()
            if failures.count == before { passed += 1; print("PASS testAnimationLoopsStopWhenHiddenPausedOrReduced") }
        }
        do {
            let before = failures.count
            try checks.testSystemAppearanceColorsAndContrast()
            if failures.count == before { passed += 1; print("PASS testSystemAppearanceColorsAndContrast") }
        } catch { failures.append("testSystemAppearanceColorsAndContrast: \(error)") }
        do {
            let before = failures.count
            checks.testMusicScrubbersClampDragAndKeyboardValues()
            if failures.count == before { passed += 1; print("PASS testMusicScrubbersClampDragAndKeyboardValues") }
        }
        do {
            let before = failures.count
            try await checks.testPopoverAppearanceFollowsSystemChangesWithoutResizing()
            if failures.count == before { passed += 1; print("PASS testPopoverAppearanceFollowsSystemChangesWithoutResizing") }
        } catch { failures.append("testPopoverAppearanceFollowsSystemChangesWithoutResizing: \(error)") }
        for failure in failures { print("FAIL \(failure)") }
        print("\(passed) checks passed, \(failures.count) failures, \(skipUIRender ? 1 : 0) skipped")
        if !failures.isEmpty { exit(1) }
    }
}
