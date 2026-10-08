import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security

@MainActor final class SpotifyService: ObservableObject {
    @Published var clientID: String
    @Published var connected = false
    @Published var connecting = false
    @Published var busy = false
    @Published var error: String?
    @Published var recovery: Recovery = .retry
    @Published var offline = false
    @Published var profile: Profile?
    @Published var playlists: [Playlist] = []
    @Published var saved: [Track] = []
    @Published var recent: [Track] = []
    @Published var topTracks: [Track] = []
    @Published var search: SearchResults?
    @Published var searching = false
    @Published var queue: [Track] = []
    @Published var devices: [Device] = []
    @Published var loadingDevices = false
    @Published var loadingQueue = false
    @Published var loadingPlaylists = false
    @Published var loadingSaved = false
    @Published var detailTitle: String?
    @Published var detailTracks: [Track] = []
    @Published var detailLoading = false
    @Published var detailNext: String?
    @Published var playlistNext: String?
    @Published var savedNext: String?
    @Published var notice: Notice?
    @Published var cachedDate: Date?
    let visualizer: AudioVisualizer
    let player: PlayerState
    let preferences: AppPreferences

    private var callbackRedirect: String?
    private let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-library-modify playlist-read-private playlist-read-collaborative user-read-recently-played user-top-read"
    private let session: URLSession
    private let cache: LibraryCache
    private let defaults: UserDefaults
    private let usesKeychain: Bool
    private let reconciliationDelay: Duration?
    private let local = LocalSpotify()
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt = Date.distantPast
    private var verifier: String?
    private var expectedState: String?
    private var listener: NWListener?
    private var listenerStopTask: Task<Void, Never>?
    private var listenerStartTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var authorizationRevision = 0
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<TokenResponse, Error>?
    private var playbackTask: Task<Playback?, Error>?
    private var playbackSavedTask: Task<Void, Never>?
    private var playbackFailures = 0
    private var playbackRefreshDeferred = false
    private var playbackError: String?
    private var lastPlaybackRequest = Date.distantPast
    private var desktopEvent: DesktopPlaybackEvent?
    private var desktopEventUntil = Date.distantPast
    private var commandTail: Task<Bool, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var detailRequestID = 0
    private var sessionRevision = 0
    private var rateLimitedUntil = Date.distantPast
    private var savedChecks: [String: Bool] = [:]
    private var savedCheckDates: [String: Date] = [:]
    private var pendingSaves: Set<String> = []
    private var saveCounts: [String: Int] = [:]
    private var saveVersions: [String: Int] = [:]
    private var confirmedSaved: [String: Bool] = [:]
    private enum MutationField: Hashable { case playback, position, volume, shuffle, repeatMode }
    private struct Mutation { let field: MutationField; let version: Int; let value: Playback? }
    private var mutationCounts: [MutationField: Int] = [:]
    private var mutationVersions: [MutationField: Int] = [:]
    private var confirmedPlayback: [MutationField: Mutation] = [:]
    private var detailKey: String?
    private var detailAlbum: Album?
    private var details: [String: ([Track], String?)] = [:]

    init(session: URLSession = .shared, cache: LibraryCache = .live, defaults: UserDefaults = .standard, initialToken: String? = nil, restore: Bool = true, reconciliationDelay: Duration? = .milliseconds(500), preferences: AppPreferences? = nil, visualizer: AudioVisualizer? = nil) {
        self.session = session; self.cache = cache; self.defaults = defaults
        self.preferences = preferences ?? AppPreferences(defaults: defaults)
        self.visualizer = visualizer ?? AudioVisualizer()
        usesKeychain = initialToken == nil; self.reconciliationDelay = reconciliationDelay
        clientID = defaults.string(forKey: "spotifyClientID") ?? ""
        player = PlayerState(defaults: defaults)
        if let initialToken {
            accessToken = initialToken; expiresAt = .distantFuture; connected = true
        } else if restore {
            refreshToken = Keychain.read("refreshToken")
            connected = refreshToken != nil
        }
        if restore && connected {
            let epoch = sessionRevision
            Task {
                let snapshot = await cache.load(clientID: clientID)
                guard epoch == sessionRevision, connected else { return }
                if let snapshot {
                    profile = snapshot.profile; playlists = snapshot.playlists; saved = snapshot.saved
                    recent = snapshot.recent; topTracks = snapshot.topTracks
                    playlistNext = snapshot.playlistNext; savedNext = snapshot.savedNext
                    player.savedIDs = snapshot.savedIDs; cachedDate = snapshot.date
                }
                await refreshAll()
            }
        }
    }

    func connect() {
        guard !connecting else { return }
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Enter your Spotify developer app's Client ID."; return }
        defaults.set(trimmed, forKey: "spotifyClientID"); clientID = trimmed
        connecting = true
        error = nil
        authorizationRevision += 1
        let revision = authorizationRevision
        let verifier = randomURLSafe(64), state = randomURLSafe(24)
        self.verifier = verifier; expectedState = state
        listenerStartTask = Task { [weak self] in
            guard let self else { return }
            if let listenerStopTask { await listenerStopTask.value }
            guard !Task.isCancelled, revision == authorizationRevision, connecting else { return }
            listenerStartTask = nil
            startCallbackListener(clientID: trimmed, verifier: verifier, state: state, revision: revision)
        }
    }
    private func startCallbackListener(clientID: String, verifier: String, state: String, revision: Int) {
        let callback: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            callback = try NWListener(using: parameters, on: .any)
        } catch {
            self.error = "Could not start Spotify sign-in. Please try again."
            connecting = false; self.verifier = nil; expectedState = nil
            return
        }
        listener = callback
        callback.newConnectionHandler = { [weak self] connection in
            guard let owner = self else { connection.cancel(); return }
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8),
                      let path = request.components(separatedBy: " ").dropFirst().first,
                      path.hasPrefix("/callback") else { connection.cancel(); return }
                let html = "<html><body style='background:#101410;color:white;font:18px system-ui;text-align:center;padding:80px'><h1>Return to SpotMenu</h1><p>You can close this tab. Your menu bar app will finish connecting.</p></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                Task { @MainActor in
                    guard let redirect = owner.callbackRedirect,
                          let callbackBase = URL(string: redirect),
                          let url = URL(string: "http://127.0.0.1:\(callbackBase.port ?? 0)" + path),
                          url.host == "127.0.0.1", url.port == callbackBase.port, url.path == "/callback" else { return }
                    owner.handleCallback(url)
                }
            }
        }
        callback.stateUpdateHandler = { [weak self, weak callback] listenerState in
            guard let self, let callback else { return }
            switch listenerState {
            case .ready:
                Task { @MainActor in
                    guard revision == self.authorizationRevision, self.connecting, self.listener === callback,
                          let port = callback.port?.rawValue, port != 0 else { return }
                    let redirect = "http://127.0.0.1:\(port)/callback"
                    self.callbackRedirect = redirect
                    var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
                    components.queryItems = [
                        .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
                        .init(name: "scope", value: self.scopes), .init(name: "redirect_uri", value: redirect),
                        .init(name: "state", value: state), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString())
                    ]
                    guard let authorizationURL = components.url else {
                        self.error = "Could not prepare Spotify sign-in. Try again."
                        self.cancelConnection()
                        return
                    }
                    NSWorkspace.shared.open(authorizationURL)
                }
            case .failed:
                Task { @MainActor in
                    guard revision == self.authorizationRevision else { return }
                    self.error = "Could not open the Spotify callback. Try again."
                    self.cancelConnection()
                }
            default: break
            }
        }
        callback.start(queue: .main)
    }
    private func stopCallbackListener() {
        guard let callback = listener else { return }
        listener = nil
        callbackRedirect = nil
        let previous = listenerStopTask
        listenerStopTask = Task {
            if let previous { await previous.value }
            await withCheckedContinuation { continuation in
                callback.stateUpdateHandler = { state in
                    if case .cancelled = state { continuation.resume() }
                }
                callback.cancel()
            }
        }
    }
    func cancelConnection() {
        authorizationRevision += 1; authorizationTask?.cancel(); authorizationTask = nil
        listenerStartTask?.cancel(); listenerStartTask = nil
        stopCallbackListener()
        connecting = false; verifier = nil; expectedState = nil
    }
    private func handleCallback(_ url: URL) {
        guard connecting, authorizationTask == nil else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { values.first { $0.name == key }?.value }
        guard value("state") == expectedState else { error = "Sign-in state did not match. Please try again."; cancelConnection(); return }
        guard let code = value("code"), let verifier else { error = value("error") ?? "Sign-in was canceled."; cancelConnection(); return }
        let redirect = callbackRedirect
        stopCallbackListener()
        guard let redirect else { error = "Spotify sign-in expired. Please try again."; cancelConnection(); return }
        let revision = authorizationRevision
        authorizationTask = Task {
            defer { if revision == authorizationRevision { connecting = false; authorizationTask = nil; self.verifier = nil; expectedState = nil } }
            do {
                let token = try await tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "client_id": clientID, "code_verifier": verifier])
                guard revision == authorizationRevision, !Task.isCancelled else { return }
                store(token)
                connected = true; error = nil
                await refreshAll()
            } catch { report(error) }
        }
    }
    func disconnect() {
        sessionRevision += 1; cancelConnection()
        searchTask?.cancel(); refreshTask?.cancel(); playbackTask?.cancel(); playbackSavedTask?.cancel(); commandTail?.cancel(); reconcileTask?.cancel(); persistTask?.cancel(); noticeTask?.cancel()
        if usesKeychain { Keychain.delete("refreshToken") }
        refreshTask = nil; playbackTask = nil; playbackSavedTask = nil
        playbackFailures = 0; playbackRefreshDeferred = false; playbackError = nil; lastPlaybackRequest = .distantPast; desktopEvent = nil; desktopEventUntil = .distantPast
        rateLimitedUntil = .distantPast; expiresAt = .distantPast
        accessToken = nil; refreshToken = nil; connected = false
        player.apply(nil); player.savedIDs = []; player.pendingCommands = 0
        profile = nil; playlists = []; saved = []; recent = []; topTracks = []; queue = []; search = nil
        savedChecks = [:]; savedCheckDates = [:]; pendingSaves = []; saveCounts = [:]; confirmedSaved = [:]
        mutationCounts = [:]; confirmedPlayback = [:]; commandTail = nil
        details = [:]; cachedDate = nil; devices = []; notice = nil; error = nil; offline = false
        playlistNext = nil; savedNext = nil; closeDetail(); player.transferringID = nil
        Task { await cache.clear() }
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { .init(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.expired }
        return try await decode(TokenResponse.self, data)
    }
    private func store(_ token: TokenResponse) {
        accessToken = token.access_token; expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        if let refresh = token.refresh_token { refreshToken = refresh; if usesKeychain { Keychain.write(refresh, "refreshToken") } }
    }
    private func validToken() async throws -> String {
        if let accessToken, Date() < expiresAt { return accessToken }
        guard let refreshToken else { throw APIError.expired }
        if let refreshTask { return try await refreshTask.value.access_token }
        let epoch = sessionRevision
        let task = Task { try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]) }
        refreshTask = task; defer { if epoch == sessionRevision { refreshTask = nil } }
        let token = try await task.value
        guard epoch == sessionRevision else { throw CancellationError() }
        store(token); return token.access_token
    }
    private func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, retry: Bool = true) async throws -> T? {
        let epoch = sessionRevision
        try Task.checkCancellation()
        if Date() < rateLimitedUntil { throw APIError.rateLimited(Int(rateLimitedUntil.timeIntervalSinceNow.rounded(.up))) }
        let urlString = path.hasPrefix("https://api.spotify.com/v1/") ? path : "https://api.spotify.com/v1" + path
        guard var components = URLComponents(string: urlString), components.host == "api.spotify.com" else { throw APIError.message("Invalid Spotify URL.") }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.message("Invalid Spotify URL.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData); request.httpMethod = method; request.timeoutInterval = 15
        do { request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization") }
        catch {
            guard epoch == sessionRevision else { throw CancellationError() }
            try Task.checkCancellation(); throw error
        }
        guard epoch == sessionRevision else { throw CancellationError() }
        try Task.checkCancellation()
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch {
            guard epoch == sessionRevision else { throw CancellationError() }
            try Task.checkCancellation(); throw error
        }
        let (data, response) = result
        guard epoch == sessionRevision else { throw CancellationError() }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw APIError.offline }
        let status = response.statusCode
        if status == 401 && retry { accessToken = nil; expiresAt = .distantPast; return try await self.request(path, method: method, query: query, body: body, retry: false) }
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw APIError.expired
            case 403: throw APIError.forbidden
            case 404: throw APIError.noDevice
            case 429:
                let seconds = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "10") ?? 10
                rateLimitedUntil = Date().addingTimeInterval(Double(seconds)); throw APIError.rateLimited(seconds)
            default: throw APIError.message("Spotify could not complete that request (\(status)). Try again.")
            }
        }
        if offline { offline = false; if recovery == .retry { error = nil } }
        if status == 204 || data.isEmpty { return nil }
        let value = try await decode(T.self, data)
        guard epoch == sessionRevision else { throw CancellationError() }
        return value
    }
    private nonisolated func decode<T: Decodable & Sendable>(_ type: T.Type, _ data: Data) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(type, from: data) }.value
    }
    private struct Empty: Decodable, Sendable {}
    private func report(_ failure: Error) {
        if failure is CancellationError || (failure as? URLError)?.code == .cancelled { return }
        if let urlError = failure as? URLError, [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut].contains(urlError.code) {
            offline = true; recovery = .retry; error = APIError.offline.localizedDescription; return
        }
        error = failure.localizedDescription
        switch failure as? APIError {
        case .expired: recovery = .reconnect
        case .noDevice: recovery = .device
        case .rateLimited: recovery = .wait
        default: recovery = .retry
        }
    }
    func dismissError() { error = nil }
    func showNotice(_ text: String, icon: String = "checkmark.circle.fill", undo: (@MainActor () -> Void)? = nil) {
        noticeTask?.cancel(); let value = Notice(message: text, icon: icon, undo: undo); notice = value
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(undo == nil ? 3 : 6))
            if !Task.isCancelled && notice?.id == value.id { notice = nil }
        }
    }
    private func persist() {
        persistTask?.cancel()
        let revision = sessionRevision
        let snapshot = LibrarySnapshot(clientID: clientID, profile: profile, playlists: playlists, saved: saved, recent: recent, topTracks: topTracks, playlistNext: playlistNext, savedNext: savedNext, savedIDs: player.savedIDs, date: Date())
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, connected, revision == sessionRevision else { return }
            await cache.save(snapshot)
        }
    }

    func refreshAll() async {
        guard connected && !busy else { return }
        busy = true; defer { busy = false }
        let epoch = sessionRevision
        async let profileTask: Void = refreshProfile(epoch)
        async let playlistTask: Void = refreshPlaylists(epoch)
        async let savedTask: Void = refreshSaved(epoch)
        async let recentTask: Void = refreshRecent(epoch)
        async let topTask: Void = refreshTop(epoch)
        async let playerTask: Void = refreshPlayback()
        _ = await (profileTask, playlistTask, savedTask, recentTask, topTask, playerTask)
        if epoch == sessionRevision { await checkSaved(recent + topTracks) }
        if epoch == sessionRevision, !offline { persist() }
    }
    private func refreshProfile(_ epoch: Int) async {
        do { let value: Profile? = try await request("/me"); if epoch == sessionRevision { profile = value; cachedDate = Date() } } catch { report(error) }
    }
    private func refreshPlaylists(_ epoch: Int) async {
        do {
            let page: Page<Playlist>? = try await request("/me/playlists", query: [.init(name: "limit", value: "30")])
            if epoch == sessionRevision, let page {
                let hadExtra = playlists.count > 30
                playlists = merge(page.items, hadExtra ? playlists : [])
                if !hadExtra { playlistNext = page.next }
            }
        } catch { report(error) }
    }
    private func refreshSaved(_ epoch: Int) async {
        do {
            let versions = saveVersions
            let page: Page<SavedTrack>? = try await request("/me/tracks", query: [.init(name: "limit", value: "30")])
            if epoch == sessionRevision, let page {
                let tracks = page.items.map(\.track), hadExtra = saved.count > 30
                let changed = saved.filter { versions[$0.stableID] != saveVersions[$0.stableID] }
                saved = merge(changed, merge(tracks, hadExtra ? saved : [])).filter { track in
                    let locallyChanged = versions[track.stableID] != saveVersions[track.stableID] || pendingSaves.contains(track.stableID)
                    return !locallyChanged || player.isSaved(track)
                }
                for track in saved where !pendingSaves.contains(track.stableID) { player.savedIDs.insert(track.stableID); savedChecks[track.stableID] = true; savedCheckDates[track.stableID] = Date() }
                if !hadExtra { savedNext = page.next }
            }
        } catch { report(error) }
    }
    private func refreshRecent(_ epoch: Int) async {
        do { let page: Page<RecentTrack>? = try await request("/me/player/recently-played", query: [.init(name: "limit", value: "20")]); if epoch == sessionRevision { recent = page?.items.map(\.track) ?? [] } } catch { report(error) }
    }
    private func refreshTop(_ epoch: Int) async {
        do { let page: Page<Track>? = try await request("/me/top/tracks", query: [.init(name: "limit", value: "20")]); if epoch == sessionRevision { topTracks = page?.items ?? [] } } catch { report(error) }
    }
    // Foreground checks stay quick even while paused. Background detection never stops.
    // The service's global Retry-After gate still applies to event-triggered checks.
    var playbackPollingDelay: Duration {
        if Date() < rateLimitedUntil { return .seconds(max(1, min(3600, rateLimitedUntil.timeIntervalSinceNow))) }
        if playbackFailures > 0 { return .seconds(min(30, pow(2, Double(min(playbackFailures, 5))))) }
        if playbackRefreshDeferred { return .seconds(max(0.01, 0.5 - Date().timeIntervalSince(lastPlaybackRequest))) }
        return .seconds(preferences.isPresented ? 2 : player.playback?.is_playing == true ? 5 : 10)
    }
    func receiveDesktopPlayback(_ event: DesktopPlaybackEvent) {
        guard connected, player.pendingCommands == 0 else { return }
        // A paused desktop app must not stop the user's active phone/speaker.
        if let device = player.playback?.device, device.is_active, device.type != "Computer" { return }
        guard let latest = event.applying(to: player.playback) else { return }
        player.revision += 1
        desktopEvent = event; desktopEventUntil = Date().addingTimeInterval(3)
        player.apply(latest)
    }
    func refreshPlayback() async {
        guard connected, player.pendingCommands == 0, playbackTask == nil else { return }
        // Coalesce notification bursts without repeatedly hitting the Web API.
        guard Date() >= rateLimitedUntil else { return }
        guard Date().timeIntervalSince(lastPlaybackRequest) >= 0.5 else { playbackRefreshDeferred = true; return }
        playbackRefreshDeferred = false; lastPlaybackRequest = Date()
        let revision = player.revision, epoch = sessionRevision
        let task = Task { try await request("/me/player") as Playback? }
        playbackTask = task; defer { if epoch == sessionRevision { playbackTask = nil } }
        do {
            let latest = try await task.value
            guard epoch == sessionRevision else { return }
            playbackFailures = 0
            if let playbackError, error == playbackError { error = nil; recovery = .retry }
            playbackError = nil
            guard revision == player.revision, player.pendingCommands == 0 else { return }
            // Connect can briefly lag a desktop event, or return 204 during a transition.
            let remote = latest?.device.map { $0.is_active && $0.type != "Computer" } ?? false
            if !remote, Date() < desktopEventUntil, let desktopEvent, !desktopEvent.agrees(with: latest) { return }
            player.apply(latest)
            if let track = latest?.item, playbackSavedTask == nil {
                playbackSavedTask = Task { [weak self] in
                    guard let self, epoch == self.sessionRevision, self.connected, !Task.isCancelled else { return }
                    await self.checkSaved([track])
                    if epoch == self.sessionRevision { self.playbackSavedTask = nil }
                }
            }
        } catch {
            guard epoch == sessionRevision else { return }
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { playbackFailures += 1 }
            report(error); playbackError = self.error
        }
    }
    func checkSaved(_ tracks: [Track]) async {
        let unchecked = Array(merge(tracks, []).filter { savedCheckDates[$0.stableID, default: .distantPast].timeIntervalSinceNow < -60 && !pendingSaves.contains($0.stableID) && $0.uri != nil }.prefix(40))
        guard !unchecked.isEmpty else { return }
        let versions = saveVersions
        do {
            let flags: [Bool]? = try await request("/me/library/contains", query: [.init(name: "uris", value: unchecked.compactMap(\.uri).joined(separator: ","))])
            for (track, flag) in zip(unchecked, flags ?? []) where !pendingSaves.contains(track.stableID) && versions[track.stableID] == saveVersions[track.stableID] {
                savedChecks[track.stableID] = flag; savedCheckDates[track.stableID] = Date()
                if flag { player.savedIDs.insert(track.stableID) } else { player.savedIDs.remove(track.stableID) }
            }
        } catch { /* Checking hearts should not interrupt browsing. */ }
    }
    func loadMorePlaylists() async {
        guard let next = playlistNext, !loadingPlaylists else { return }
        loadingPlaylists = true; defer { loadingPlaylists = false }
        let epoch = sessionRevision
        do { let page: Page<Playlist>? = try await request(next); if epoch == sessionRevision, let page { playlists = merge(playlists, page.items); playlistNext = page.next; persist() } } catch { report(error) }
    }
    func loadMoreSaved() async {
        guard let next = savedNext, !loadingSaved else { return }
        loadingSaved = true; defer { loadingSaved = false }
        let epoch = sessionRevision
        do {
            let page: Page<SavedTrack>? = try await request(next)
            if epoch == sessionRevision, let page {
                let tracks = page.items.map(\.track); saved = merge(saved, tracks); savedNext = page.next
                for track in tracks where !pendingSaves.contains(track.stableID) { player.savedIDs.insert(track.stableID); savedChecks[track.stableID] = true }
                persist()
            }
        } catch { report(error) }
    }
    func loadQueue() async {
        guard connected, !loadingQueue else { return }; loadingQueue = true; defer { loadingQueue = false }
        do { queue = try await (request("/me/player/queue") as QueueResult?)?.queue ?? [] } catch { report(error) }
    }
    func loadDevices() async {
        guard connected, !loadingDevices else { return }; loadingDevices = true; defer { loadingDevices = false }
        do { devices = try await (request("/me/player/devices") as DeviceList?)?.devices ?? [] } catch { report(error) }
    }
    func searchFor(_ text: String) {
        searchTask?.cancel(); let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { search = nil; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            do {
                let result: SearchResults? = try await request("/search", query: [.init(name: "q", value: query), .init(name: "type", value: "track,album,artist,playlist"), .init(name: "limit", value: "10")])
                guard !Task.isCancelled else { return }
                search = result; searching = false
                await checkSaved(result?.tracks?.items ?? [])
            } catch { if !Task.isCancelled { searching = false; report(error) } }
        }
    }
    func closeDetail() { detailRequestID += 1; detailTitle = nil; detailTracks = []; detailNext = nil; detailLoading = false; detailKey = nil }
    func openPlaylist(_ playlist: Playlist) async {
        guard let id = playlist.id else { return }
        await loadDetail(key: "playlist:\(id)", title: playlist.name, path: "/playlists/\(id)/items", album: nil)
    }
    func openAlbum(_ album: Album) async {
        guard let id = album.id else { return }
        await loadDetail(key: "album:\(id)", title: album.name, path: "/albums/\(id)/tracks", album: album)
    }
    private func loadDetail(key: String, title: String, path: String, album: Album?) async {
        detailRequestID += 1; let id = detailRequestID
        detailKey = key; detailAlbum = album; detailTitle = title
        detailTracks = details[key]?.0 ?? []; detailNext = details[key]?.1; detailLoading = true
        do {
            let (tracks, next) = try await detailPage(path, album: album)
            guard id == detailRequestID else { return }
            detailTracks = tracks; detailNext = next; detailLoading = false; details[key] = (tracks, next)
            await checkSaved(tracks)
        } catch { if id == detailRequestID { detailLoading = false; report(error) } }
    }
    private func detailPage(_ path: String, album: Album?) async throws -> ([Track], String?) {
        if let album {
            let page: Page<Track>? = try await request(path)
            return (page?.items.map { Track(id: $0.id, name: $0.name, uri: $0.uri, duration_ms: $0.duration_ms, artists: $0.artists, album: album) } ?? [], page?.next)
        }
        let page: Page<PlaylistItem>? = try await request(path)
        return (page?.items.compactMap(\.resolved) ?? [], page?.next)
    }
    func loadMoreDetail() async {
        guard let next = detailNext, !detailLoading else { return }
        detailLoading = true; let id = detailRequestID
        do {
            let (tracks, newNext) = try await detailPage(next, album: detailAlbum)
            guard id == detailRequestID else { return }
            detailTracks += tracks; detailNext = newNext; detailLoading = false
            if let key = detailKey { details[key] = (detailTracks, newNext) }
            await checkSaved(tracks)
        } catch { if id == detailRequestID { detailLoading = false; report(error) } }
    }
    func activate(_ entry: SearchEntry) async {
        switch entry {
        case .track(let track): await play(track)
        case .album(let album): await openAlbum(album)
        case .playlist(let playlist): await openPlaylist(playlist)
        case .artist(let artist): if let uri = artist.uri { openSpotify(uri) }
        }
    }
    func openSpotify(_ uri: String?) {
        guard let uri else { return }
        let parts = uri.split(separator: ":")
        if parts.count == 3, parts[0] == "spotify", let link = URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])") { NSWorkspace.shared.open(link) }
        else if let link = URL(string: uri), link.host == "open.spotify.com", link.scheme == "https" { NSWorkspace.shared.open(link) }
    }
    var detailURI: String? { detailKey.map { "spotify:" + $0 } }

    @discardableResult private func send(_ path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, localFallback: String? = nil, refreshAfter: Bool = true) async -> Bool {
        let previous = commandTail, epoch = sessionRevision
        if path == "/me/player/next" || path == "/me/player/previous" { desktopEvent = nil; desktopEventUntil = .distantPast }
        player.pendingCommands += 1; reconcileTask?.cancel()
        let task = Task { [weak self] () -> Bool in
            if let previous { _ = await previous.value }
            guard let self else { return false }
            defer { if epoch == self.sessionRevision { self.player.pendingCommands = max(0, self.player.pendingCommands - 1) } }
            guard self.connected, epoch == self.sessionRevision else { return false }
            var success = false
            do { let _: Empty? = try await self.request(path, method: method, query: query, body: body); self.error = nil; success = true }
            catch {
                guard epoch == self.sessionRevision, !Task.isCancelled else { return false }
                let canFallback: Bool
                switch error as? APIError { case .expired, .rateLimited: canFallback = false; default: canFallback = true }
                if let localFallback, canFallback, self.preferences.desktopFallback, await self.local.execute(localFallback) { success = true; self.error = nil }
                else { self.report(error) }
            }
            if refreshAfter { self.scheduleReconciliation() }
            return success
        }
        commandTail = task
        return await task.value
    }
    private func scheduleReconciliation() {
        reconcileTask?.cancel()
        guard let reconciliationDelay else { return }
        reconcileTask = Task {
            try? await Task.sleep(for: reconciliationDelay)
            if !Task.isCancelled { await refreshPlayback() }
        }
    }
    private func optimistic(_ field: MutationField, _ mutate: (inout Playback) -> Void) -> Mutation {
        let original = player.playback
        if field == .playback { desktopEvent = nil; desktopEventUntil = .distantPast }
        player.revision += 1
        let version = player.revision
        if mutationCounts[field, default: 0] == 0 { confirmedPlayback[field] = Mutation(field: field, version: version, value: original) }
        mutationCounts[field, default: 0] += 1; mutationVersions[field] = version
        if var state = original { mutate(&state); player.apply(state) }
        return Mutation(field: field, version: version, value: player.playback)
    }
    private func copying(_ field: MutationField, from source: Playback?, to destination: Playback?) -> Playback? {
        guard var value = destination, let source else { return field == .playback ? source : destination }
        switch field {
        case .playback: value.item = source.item; value.is_playing = source.is_playing; value.progress_ms = source.progress_ms
        case .position: value.progress_ms = source.progress_ms
        case .volume: value.device?.volume_percent = source.device?.volume_percent
        case .shuffle: value.shuffle_state = source.shuffle_state
        case .repeatMode: value.repeat_state = source.repeat_state
        }
        return value
    }
    private func complete(_ mutation: Mutation, success: Bool) {
        guard let confirmed = confirmedPlayback[mutation.field] else { return }
        if success { confirmedPlayback[mutation.field] = Mutation(field: mutation.field, version: mutation.version, value: copying(mutation.field, from: mutation.value, to: confirmed.value ?? mutation.value)) }
        else if mutationVersions[mutation.field] == mutation.version { player.apply(copying(mutation.field, from: confirmed.value, to: player.playback)) }
        mutationCounts[mutation.field, default: 1] -= 1
        if mutationCounts[mutation.field] == 0 { confirmedPlayback[mutation.field] = nil }
    }
    func togglePlayback() async {
        let playing = player.playback?.is_playing == true
        let mutation = optimistic(.playback) { $0.is_playing = !playing }
        complete(mutation, success: await send(playing ? "/me/player/pause" : "/me/player/play", method: "PUT", localFallback: playing ? "pause" : "play"))
    }
    func play(_ track: Track, contextURI: String? = nil, following: [Track]? = nil, contextPosition: Int? = nil) async {
        guard let uri = track.uri else { return }
        let original = player.playback
        let mutation = optimistic(.playback) { $0.item = track; $0.progress_ms = 0; $0.is_playing = true }
        let state = Playback(is_playing: true, progress_ms: 0, repeat_state: original?.repeat_state ?? "off", shuffle_state: original?.shuffle_state ?? false, item: track, device: original?.device)
        player.apply(state)
        // A one-item URI list discards the album/playlist context used by Spotify Autoplay.
        let albumURI = track.album?.uri ?? track.album?.id.map { "spotify:album:\($0)" }
        let context = contextURI ?? (preferences.continuousPlayback && following == nil ? albumURI : nil)
        let object: [String: Any]
        if let context {
            let offset: [String: Any] = contextPosition.map { ["position": max(0, $0)] } ?? ["uri": uri]
            object = ["context_uri": context, "offset": offset, "position_ms": 0]
        } else {
            let next = preferences.continuousPlayback ? (following ?? []).compactMap(\.uri) : []
            object = ["uris": [uri] + Array(next.prefix(99)), "position_ms": 0]
        }
        let body = try? JSONSerialization.data(withJSONObject: object)
        let target = Mutation(field: .playback, version: mutation.version, value: state)
        let fallback = "play track \"\(safeURI(uri))\"" + (context.map { " in context \"\(safeURI($0))\"" } ?? "")
        complete(target, success: await send("/me/player/play", method: "PUT", body: body, localFallback: fallback))
    }
    func playCollection() async { if let first = detailTracks.first { await play(first, contextURI: detailURI) } }
    func next() async { await send("/me/player/next", method: "POST", localFallback: "next track") }
    func previous() async { await send("/me/player/previous", method: "POST", localFallback: "previous track") }
    func seek(_ milliseconds: Int) async {
        let position = max(0, milliseconds), mutation = optimistic(.position) { $0.progress_ms = position }
        complete(mutation, success: await send("/me/player/seek", method: "PUT", query: [.init(name: "position_ms", value: String(position))], localFallback: "set player position to \(position / 1000)"))
    }
    func volume(_ percent: Int) async {
        let percent = min(100, max(0, percent)), prior = player.volume
        player.setVolume(Double(percent))
        let mutation = optimistic(.volume) { $0.device?.volume_percent = percent }
        let success = await send("/me/player/volume", method: "PUT", query: [.init(name: "volume_percent", value: String(percent))], localFallback: "set sound volume to \(percent)")
        complete(mutation, success: success)
        if !success, mutationVersions[.volume] == mutation.version, player.playback?.device?.volume_percent == nil { player.setVolume(prior) }
    }
    func shuffle() async {
        let desired = player.playback?.shuffle_state != true
        let mutation = optimistic(.shuffle) { $0.shuffle_state = desired }
        complete(mutation, success: await send("/me/player/shuffle", method: "PUT", query: [.init(name: "state", value: String(desired))]))
    }
    func repeatMode() async {
        let current = player.playback?.repeat_state ?? "off", next = current == "off" ? "context" : current == "context" ? "track" : "off"
        let mutation = optimistic(.repeatMode) { $0.repeat_state = next }
        complete(mutation, success: await send("/me/player/repeat", method: "PUT", query: [.init(name: "state", value: next)]))
    }
    func addToQueue(_ track: Track) async {
        guard let uri = track.uri else { return }
        if await send("/me/player/queue", method: "POST", query: [.init(name: "uri", value: uri)], refreshAfter: false) {
            queue.append(track); showNotice("Added to queue", icon: "text.badge.plus")
        }
    }
    func transfer(to device: Device) async {
        guard let id = device.id, player.transferringID == nil, device.is_restricted != true else { return }
        player.transferringID = id; defer { player.transferringID = nil }
        let body = try? JSONSerialization.data(withJSONObject: ["device_ids": [id], "play": player.playback?.is_playing ?? true] as [String: Any])
        if await send("/me/player", method: "PUT", body: body) { showNotice("Connected to \(device.name)", icon: "hifispeaker.fill"); await loadDevices() }
    }
    func setSaved(_ track: Track, to desired: Bool) async {
        guard let uri = track.uri, connected else { return }
        let original = player.isSaved(track), oldList = saved
        let epoch = sessionRevision, key = track.stableID
        let version = saveVersions[key, default: 0] + 1; saveVersions[key] = version
        if saveCounts[key, default: 0] == 0 { confirmedSaved[key] = original }
        saveCounts[key, default: 0] += 1; pendingSaves.insert(key)
        defer {
            if epoch == sessionRevision {
                saveCounts[key, default: 1] -= 1
                if saveCounts[key] == 0 { pendingSaves.remove(key); confirmedSaved[key] = nil }
            }
        }
        if desired { player.savedIDs.insert(track.stableID); saved = merge([track], saved) }
        else { player.savedIDs.remove(track.stableID); saved.removeAll { $0.stableID == track.stableID } }
        if await send("/me/library", method: desired ? "PUT" : "DELETE", query: [.init(name: "uris", value: uri)], refreshAfter: false) {
            guard epoch == sessionRevision else { return }
            confirmedSaved[key] = desired; savedChecks[key] = desired; savedCheckDates[key] = Date(); persist()
            showNotice(desired ? "Saved to Liked Songs" : "Removed from Liked Songs", icon: desired ? "heart.fill" : "heart.slash") { [weak self] in
                Task { await self?.setSaved(track, to: original) }
            }
        } else {
            guard epoch == sessionRevision, saveVersions[key] == version else { return }
            let baseline = confirmedSaved[key] ?? original
            if baseline { player.savedIDs.insert(track.stableID) } else { player.savedIDs.remove(track.stableID) }
            saved.removeAll { $0.stableID == track.stableID }
            if baseline, let priorTrack = oldList.first(where: { $0.stableID == track.stableID }) {
                saved.insert(priorTrack, at: min(oldList.firstIndex(where: { $0.stableID == track.stableID }) ?? 0, saved.count))
            } else if baseline { saved.insert(track, at: 0) }
            persist()
        }
    }
    func save(_ track: Track, saved: Bool) async { await setSaved(track, to: !saved) }
}

private func merge<T: SpotifyIdentifiable>(_ first: [T], _ second: [T]) -> [T] {
    var seen = Set<String>()
    return (first + second).filter { seen.insert($0.stableID).inserted }
}
private func randomURLSafe(_ count: Int) -> String {
    let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return String((0..<count).compactMap { _ in chars.randomElement() })
}
private func safeURI(_ uri: String) -> String { uri.filter { $0.isLetter || $0.isNumber || $0 == ":" } }
private extension Data {
    func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
private enum Keychain {
    static let service = "com.spotmenu.auth"
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, _ key: String) {
        delete(key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(query as CFDictionary, nil)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    }
}
