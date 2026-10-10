import SwiftUI
import Combine

struct PlayerBar: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var player: PlayerState
    @EnvironmentObject private var preferences: AppPreferences
    let compact: Bool
    @Environment(\.motionReduced) private var reduceMotion
    @State private var playTaps = 0
    private var playing: Bool { player.playback?.is_playing == true }
    var body: some View {
        VStack(spacing: compact ? 0 : 10) {
            HStack(spacing: 11) {
                Button { spotify.openSpotify(player.playback?.item?.uri) } label: {
                    ZStack {
                        CoverArt(url: player.playback?.item?.imageURL, size: compact ? 46 : 64, radius: compact ? 10 : 13)
                            .id(player.playback?.item?.stableID)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.86)))
                    }
                    .frame(width: compact ? 46 : 64, height: compact ? 46 : 64)
                    .modifier(AudioBeatPulse(visualizer: spotify.visualizer))
                    .scaleEffect(playing || reduceMotion ? 1 : 0.9)
                    .shadow(color: Palette.shadow.opacity(playing ? 1 : 0.3), radius: playing ? 9 : 3, y: playing ? 4 : 1)
                    .animation(Motion.animation(reduced: reduceMotion), value: playing)
                    .animation(Motion.animation(reduced: reduceMotion), value: player.playback?.item?.stableID)
                }.buttonStyle(PressStyle(scale: 0.96)).help("Open in Spotify")
                VStack(alignment: .leading, spacing: 4) {
                    if !compact {
                        HStack(spacing: 5) {
                            LivePlayingIndicator(visualizer: spotify.visualizer, playing: playing, width: 15, height: 11)
                            Text(player.playback?.item == nil ? "YOUR PLAYER" : playing ? "NOW PLAYING" : "PAUSED").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.green)
                            if player.pendingCommands > 0 { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10) }
                        }
                    }
                    Text(player.playback?.item?.name ?? "Ready when you are")
                        .font(.system(size: compact ? 13 : 17, weight: .bold, design: .rounded)).lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(Motion.animation(reduced: reduceMotion), value: player.playback?.item?.stableID)
                    HStack(spacing: 5) {
                        if compact { LivePlayingIndicator(visualizer: spotify.visualizer, playing: playing, width: 13, height: 10) }
                        Text(player.playback?.item?.artistLine ?? "Start playing on a Spotify device").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if compact { transport(compact: true) }
                else if let track = player.playback?.item {
                    IconButton(icon: player.isSaved(track) ? "heart.fill" : "heart", label: "Like song", active: player.isSaved(track)) { Task { await spotify.setSaved(track, to: !player.isSaved(track)) } }
                }
            }
            if !compact {
                HStack(spacing: 19) {
                    IconButton(icon: "shuffle", label: "Shuffle", active: player.playback?.shuffle_state == true) { Task { await spotify.shuffle() } }
                    transport(compact: false)
                    IconButton(icon: player.playback?.repeat_state == "track" ? "repeat.1" : "repeat", label: "Repeat", active: (player.playback?.repeat_state ?? "off") != "off") { Task { await spotify.repeatMode() } }
                }.frame(maxWidth: .infinity)
                SeekBar()
                HStack(spacing: 8) {
                    Button {
                        preferences.showingDevices = true
                        Task { await spotify.loadDevices() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hifispeaker.and.homepod")
                            Text(player.playback?.device?.name ?? "Choose a device").lineLimit(1)
                            if player.transferringID != nil { ProgressView().controlSize(.mini) }
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                    }.buttonStyle(PressStyle(scale: 0.97)).frame(maxWidth: .infinity, alignment: .leading)
                    VolumeControl().frame(width: 105)
                }
            }
        }.padding(compact ? 12 : 13)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    LinearGradient(colors: [Palette.surface, Palette.raised.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    PlayerGlow(playing: playing)
                }.clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(LinearGradient(colors: [Palette.sheen, Palette.border], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: Palette.shadow.opacity(0.6), radius: 12, y: 5)
    }
    private func transport(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 16) {
            IconButton(icon: "backward.end.fill", label: "Previous track", size: compact ? 13 : 17) { Task { await spotify.previous() } }
            Button { playTaps += 1; Task { await spotify.togglePlayback() } } label: {
                Image(systemName: player.playback?.is_playing == true ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 13 : 17, weight: .bold)).foregroundStyle(Palette.onAccent)
                    .modifier(SymbolFeedback(trigger: playTaps * 2 + (playing ? 1 : 0)))
                    .frame(width: compact ? 32 : 36, height: compact ? 32 : 36).background(Palette.green.gradient, in: Circle())
                    .shadow(color: Palette.green.opacity(playing ? 0.32 : 0), radius: 8, y: 2)
            }.buttonStyle(PressStyle()).help("Play / Pause · Space").accessibilityLabel(player.playback?.is_playing == true ? "Pause" : "Play")
            IconButton(icon: "forward.end.fill", label: "Next track", size: compact ? 13 : 17) { Task { await spotify.next() } }
        }
    }
}

private struct VolumeControl: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var player: PlayerState
    @State private var value = 50.0
    @State private var editing = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: value == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 10)).foregroundStyle(Palette.muted)
                .modifier(SymbolFeedback(trigger: Int(value) / 33))
            MusicSlider(value: $value, range: 0...100, label: "Volume", valueDescription: "\(Int(value)) percent", onEditingChanged: { active in
                editing = active
                if !active { Task { await spotify.volume(Int(value)) } }
            })
                .disabled(player.playback?.device?.supports_volume == false)
                .accessibilityLabel("Volume")
        }.onAppear { value = player.volume }
            .onChange(of: player.volume) { _, new in if !editing { value = new } }
    }
}

private struct SeekBar: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var player: PlayerState
    @EnvironmentObject private var preferences: AppPreferences
    @State private var position = 0.0
    @State private var seeking = false
    var body: some View {
        VStack(spacing: 1) {
            MusicSlider(value: $position, range: 0...Double(max(player.playback?.item?.duration_ms ?? 1, 1)), label: "Playback position", valueDescription: timeString(Int(position)), smoothUpdates: true, step: 5000, waveform: spotify.visualizer, playing: player.playback?.is_playing == true, onEditingChanged: { editing in
                seeking = editing
                if !editing { Task { await spotify.seek(Int(position)) } }
            }).disabled(player.playback?.item == nil).accessibilityLabel("Playback position")
            HStack { Text(timeString(Int(position))); Spacer(); Text(timeString(player.playback?.item?.duration_ms ?? 0)) }
                .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
        }
        .onAppear { resetPosition() }
        .onChange(of: player.playback?.item?.stableID) { _, _ in resetPosition() }
        .onChange(of: player.playback?.progress_ms) { _, value in if !seeking { position = Double(value ?? 0) } }
        .task(id: preferences.isPresented && !preferences.compact) {
            guard preferences.isPresented, !preferences.compact else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if player.playback?.is_playing == true && !seeking { position = min(position + 1000, Double(player.playback?.item?.duration_ms ?? 0)) }
            }
        }
    }
    private func resetPosition() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { position = Double(player.playback?.progress_ms ?? 0) }
    }
    private func timeString(_ value: Int) -> String { let seconds = max(0, value / 1000); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
