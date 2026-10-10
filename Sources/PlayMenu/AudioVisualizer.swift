import AppKit
import Combine
import Foundation

enum VisualizerStatus: Equatable {
    case off, suspended, starting, listening, remote, unavailable(String)
    var message: String {
        switch self {
        case .off: "Playback animation"
        case .suspended: "Live audio pauses with music, hidden menus, and Reduce Motion."
        case .starting: "Connecting to Spotify audio…"
        case .listening: "Listening to Spotify on this Mac"
        case .remote: "Live audio needs Spotify playing on this Mac."
        case .unavailable(let message): message
        }
    }
}

@MainActor final class AudioVisualizer: ObservableObject {
    @Published private(set) var frame = AudioFrame.zero
    @Published private(set) var status: VisualizerStatus = .off
    @Published private(set) var lastError: String?
    private let capture: any AudioCapturing
    private var task: Task<Void, Never>?
    private var generation = 0
    private var intent: Intent?
    private var subscriptions = Set<AnyCancellable>()
    private weak var player: PlayerState?
    private weak var preferences: AppPreferences?
    private struct Intent: Equatable { let enabled: Bool; let active: Bool; let remote: Bool; let track: String? }

    init(capture: any AudioCapturing = SpotifyAudioCapture()) { self.capture = capture }
    func bind(player: PlayerState, preferences: AppPreferences) {
        self.player = player; self.preferences = preferences
        subscriptions.removeAll()
        let changes: [AnyPublisher<Void, Never>] = [
            player.$playback.map { _ in () }.eraseToAnyPublisher(),
            preferences.$liveVisualizer.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isPresented.map { _ in () }.eraseToAnyPublisher(),
            preferences.$animations.map { _ in () }.eraseToAnyPublisher(),
            preferences.$showingSettings.map { _ in () }.eraseToAnyPublisher(),
            preferences.$showingDevices.map { _ in () }.eraseToAnyPublisher(),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification).map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reconcile() }.store(in: &subscriptions)
    }
    private func reconcile() {
        guard let preferences, let player else { return }
        let active = preferences.isPresented && preferences.animations && !preferences.showingSettings && !preferences.showingDevices && player.playback?.is_playing == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        update(enabled: preferences.liveVisualizer, active: active, remote: player.playback?.device.map { $0.type != "Computer" } ?? false, track: player.playback?.item?.stableID)
    }
    func update(enabled: Bool, active: Bool, remote: Bool, track: String?) {
        let next = Intent(enabled: enabled, active: active, remote: remote, track: track)
        guard next != intent else { return }
        intent = next; generation += 1
        let token = generation, previous = task
        previous?.cancel(); frame = .zero
        if !enabled { lastError = nil }
        status = !enabled ? .off : remote ? .remote : !active ? .suspended : .starting
        let shouldStart = enabled && active && !remote
        let capture = self.capture
        // Serialize teardown/startup so a cancelled start cannot tear down a newer capture.
        task = Task { [weak self] in
            if let previous { await previous.value }
            await capture.stop()
            guard !Task.isCancelled, shouldStart else { return }
            do {
                try await capture.start { [weak self] frame in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.frame = frame
                    }
                }
                guard let self, self.generation == token, !Task.isCancelled else { await capture.stop(); return }
                self.lastError = nil
                self.status = .listening
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.status = .unavailable(error.localizedDescription)
            }
        }
    }
    func shutdown() { update(enabled: false, active: false, remote: false, track: nil) }
    func settle() async { await task?.value }
}
