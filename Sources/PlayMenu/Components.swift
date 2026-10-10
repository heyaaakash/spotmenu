import AppKit
import SwiftUI

struct CoverArt: View {
    let url: URL?
    let size: CGFloat
    var radius: CGFloat = 8
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale
    private var pixels: Int { max(32, Int(size * scale)) }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.green.opacity(0.38), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(nsImage: image).resizable().scaledToFit().transition(.opacity) }
            else { Image(systemName: "music.note").font(.system(size: size * 0.28)).foregroundStyle(Palette.muted) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.22), value: image != nil)
        .task(id: "\(url?.absoluteString ?? ""):\(pixels)") {
            guard let url else { image = nil; return }
            let key = artworkKey(url, pixels) as NSString
            if let cached = MemoryArtwork.cache.object(forKey: key) { image = cached; return }
            image = nil
            guard let data = await ArtworkCache.shared.thumbnail(url: url, pixels: pixels), !Task.isCancelled, let value = NSImage(data: data) else { return }
            MemoryArtwork.cache.setObject(value, forKey: key, cost: pixels * pixels * 4)
            image = value
        }
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PressFeedback(pressed: configuration.isPressed, scale: scale))
    }
}
private struct PressFeedback: ViewModifier {
    let pressed: Bool
    let scale: CGFloat
    @State private var hovering = false
    @Environment(\.motionReduced) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(pressed ? 0.82 : 1)
            .scaleEffect(reduceMotion ? 1 : pressed ? scale : hovering ? 1.018 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.press, value: pressed)
            .animation(Motion.animation(reduced: reduceMotion), value: hovering)
            .onHover { hovering = $0 }
    }
}
struct CardSurface: ViewModifier {
    var active = false
    @Environment(\.motionReduced) private var reduceMotion
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.background(active ? Palette.green.opacity(0.12) : hovering ? Palette.raised : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Palette.green.opacity(0.4) : Palette.border))
            .onHover { hovering = $0 }
            .shadow(color: hovering ? Palette.shadow : .clear, radius: 7, y: 3)
            .animation(Motion.animation(reduced: reduceMotion), value: hovering)
            .animation(Motion.animation(reduced: reduceMotion), value: active)
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    var active = false
    var size: CGFloat = 15
    let action: () -> Void
    @State private var taps = 0
    var body: some View {
        Button { taps += 1; action() } label: {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? Palette.green : Palette.primary.opacity(0.85))
                .modifier(SymbolFeedback(trigger: taps * 2 + (active ? 1 : 0)))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).help(label).accessibilityLabel(label)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var player: PlayerState
    let track: Track
    var selected = false
    var onPlay: (() -> Void)? = nil
    var playAction: (() async -> Void)? = nil
    var contextURI: String? = nil
    var following: [Track]? = nil
    var contextPosition: Int? = nil
    private var current: Bool { player.playback?.item?.stableID == track.stableID }
    var body: some View {
        HStack(spacing: 5) {
            Button { play() } label: {
                HStack(spacing: 11) {
                    CoverArt(url: track.imageURL, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(current ? Palette.green : Palette.primary).lineLimit(1)
                        HStack(spacing: 5) {
                            if current { PlayingWaveform(playing: player.playback?.is_playing == true, width: 14, height: 11) }
                            Text(track.artistLine).lineLimit(1)
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle(scale: 0.985)).frame(maxWidth: .infinity)
                .accessibilityLabel("Play \(track.name) by \(track.artistLine)")
            IconButton(icon: player.isSaved(track) ? "heart.fill" : "heart", label: player.isSaved(track) ? "Remove from Liked Songs" : "Save to Liked Songs", active: player.isSaved(track), size: 13) {
                Task { await spotify.setSaved(track, to: !player.isSaved(track)) }
            }
            Menu {
                Button("Play now", systemImage: "play.fill") { play() }
                Button("Add to queue", systemImage: "text.badge.plus") { Task { await spotify.addToQueue(track) } }
                Button("Open in Spotify", systemImage: "arrow.up.right.square") { spotify.openSpotify(track.uri) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 24, height: 30) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 24).help("Track actions")
        }
        .padding(8).frame(maxWidth: .infinity)
        .modifier(CardSurface(active: current || selected))
    }
    private func play() {
        onPlay?()
        spotify.beginTrackSelection()
        Task {
            defer { spotify.endTrackSelection() }
            if let playAction { await playAction() }
            else { await spotify.play(track, contextURI: contextURI, following: following, contextPosition: contextPosition) }
        }
    }
}

struct PlaylistRow: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 8) {
            Button { Task { await spotify.openPlaylist(playlist) } } label: {
                HStack(spacing: 11) {
                    CoverArt(url: playlist.imageURL, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("Playlist").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle(scale: 0.985)).frame(maxWidth: .infinity)
            IconButton(icon: preferences.pinnedIDs.contains(playlist.stableID) ? "pin.fill" : "pin", label: "Pin playlist", active: preferences.pinnedIDs.contains(playlist.stableID), size: 13) {
                preferences.togglePin(playlist)
                spotify.showNotice(preferences.pinnedIDs.contains(playlist.stableID) ? "Playlist pinned" : "Playlist unpinned", icon: "pin.fill")
            }
            IconButton(icon: "arrow.up.right", label: "Open playlist in Spotify", size: 12) { spotify.openSpotify(playlist.uri) }
        }.padding(8).frame(maxWidth: .infinity).modifier(CardSurface())
    }
}

struct SectionLabel: View {
    let title: String
    let icon: String
    var body: some View { Label(title, systemImage: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.primary).labelStyle(.titleAndIcon) }
}
struct EmptyCard: View {
    let title: String
    let text: String
    let icon: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Palette.green)
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
            Text(text).font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 265)
        }.frame(maxWidth: .infinity).padding(.vertical, 23).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
struct LoadMoreButton: View {
    let title: String
    let loading: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { HStack(spacing: 8) { if loading { ProgressView().controlSize(.small) }; Text(loading ? "Loading…" : title); if !loading { Image(systemName: "chevron.down") } }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green).frame(maxWidth: .infinity).padding(11) }
            .buttonStyle(.plain).disabled(loading)
    }
}
struct FilterPill: View {
    @Environment(\.motionReduced) private var reduceMotion
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 7).foregroundStyle(selected ? Palette.onAccent : Palette.muted).background(selected ? Palette.green : Palette.raised, in: Capsule()) }.buttonStyle(PressStyle()).animation(Motion.animation(reduced: reduceMotion), value: selected)
    }
}
