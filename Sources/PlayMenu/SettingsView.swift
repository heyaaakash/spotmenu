import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Sheet(title: "Settings", close: { preferences.showingSettings = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 32)).foregroundStyle(Palette.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spotify.profile?.display_name ?? "Your Spotify account").font(.headline)
                            Text(spotify.connected ? (spotify.offline ? "Offline · Your library is cached" : "Connected to Spotify") : "Connect Spotify to get started")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }.padding(.bottom, 2)

                    group("Appearance", icon: "circle.lefthalf.filled") {
                        HStack(spacing: 4) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Button { preferences.appearance = mode } label: {
                                    Text(mode.rawValue).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .foregroundStyle(preferences.appearance == mode ? Palette.green : Palette.muted)
                                        .background(preferences.appearance == mode ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(PressStyle()).accessibilityLabel("\(mode.rawValue) color mode")
                                    .accessibilityAddTraits(preferences.appearance == mode ? .isSelected : [])
                            }
                        }.padding(4).background(Palette.raised, in: RoundedRectangle(cornerRadius: 11))
                        caption(preferences.appearance == .auto ? "Auto follows your Mac’s appearance instantly." : "Applies to both the mini player and full menu.")
                        Divider().overlay(Palette.border)
                        setting("Animated interactions", detail: "Artwork glow, equalizer, and spring transitions. Your Mac’s Reduce Motion setting is always respected.", value: $preferences.animations)
                        setting("Playing indicator", detail: "Show a waveform in the menu bar while music plays.", value: $preferences.playingIcon)
                    }

                    group("Music visuals", icon: "waveform.path") {
                        LiveVisualizerSettings(visualizer: spotify.visualizer)
                    }

                    group("Playback", icon: "play.circle") {
                        setting("Continuous playback", detail: "Continue through loaded Liked Songs and queue tracks, or through the selected song’s album.", value: $preferences.continuousPlayback)
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Similar songs after the collection", systemImage: "sparkles").font(.system(size: 11, weight: .semibold))
                            caption("In Spotify Settings, enable Autoplay on the device playing your music. Spotify chooses the recommendations; PlayMenu cannot change this setting for you.")
                            Link("How to enable Spotify Autoplay ↗", destination: URL(string: "https://support.spotify.com/us/article/autoplay/")!)
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                        setting("Use Spotify on this Mac as fallback", detail: "Try the desktop app if Spotify Connect cannot complete a playback command.", value: $preferences.desktopFallback)
                    }

                    group("Search & privacy", icon: "magnifyingglass") {
                        setting("Remember recent searches", detail: "Keep up to eight searches on this Mac. Switching this off clears your search history.", value: $preferences.rememberSearches)
                        Button("Clear search history") { preferences.recentSearches = [] }
                            .buttonStyle(.plain).foregroundStyle(Palette.green).disabled(preferences.recentSearches.isEmpty)
                            .font(.system(size: 11, weight: .medium))
                    }

                    group("Keyboard shortcuts", icon: "keyboard") {
                        shortcut("Open / close PlayMenu", "⌘⇧Space")
                        shortcut("Search", "⌘K")
                        shortcut("Settings", "⌘,")
                        shortcut("Play / pause", "Space")
                        shortcut("Choose a search result", "↑ ↓ Return")
                        shortcut("Back / close", "Esc")
                    }

                    group("Account", icon: "person.crop.circle") {
                        if let date = spotify.cachedDate { caption("Library refreshed \(date.formatted(date: .abbreviated, time: .shortened))") }
                        if spotify.connected {
                            Button("Reconnect Spotify") { preferences.showingSettings = false; spotify.connect() }
                                .foregroundStyle(Palette.green)
                            Button("Disconnect Spotify") { preferences.showingSettings = false; spotify.disconnect() }
                                .foregroundStyle(.red)
                        }
                        Button("Quit PlayMenu") { NSApp.terminate(nil) }.foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain).font(.system(size: 12))
                    Text("PlayMenu \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")").font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top, 4)
                }.padding(.trailing, 3).padding(.bottom, 10)
            }.tint(Palette.green)
        }
    }

    private func group<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.green)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border))
    }
    private func setting(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: value) {
                Text(title).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)
            caption(detail)
        }
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.green) }
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
    }
}
