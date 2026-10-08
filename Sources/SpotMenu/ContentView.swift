import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.motionReduced) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || !preferences.animations }
    let mode: PopoverMode
    private var compact: Bool { mode == .compact }
    private var active: Bool { preferences.isPresented && (spotify.connected ? preferences.compact == compact : !compact) }
    private var sheetTransition: AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity) }
    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            RadialGradient(colors: [Palette.green.opacity(0.12), .clear], center: .topLeading, startRadius: 10, endRadius: 320).ignoresSafeArea()
            if spotify.connected {
                VStack(spacing: 0) {
                    AppHeader(compact: compact)
                    PlayerBar(compact: compact).padding(.horizontal, 16).padding(.bottom, compact ? 12 : 13)
                    if !compact {
                        BrowseArea()
                        AppTabBar()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .modifier(MenuEntrance(visible: active))
            } else { OnboardingView() }
            if !compact && preferences.showingSettings { SettingsView().transition(sheetTransition).zIndex(2) }
            if !compact && preferences.showingDevices { DevicesView().transition(sheetTransition).zIndex(3) }
        }
        .frame(width: PopoverLayout.width, height: PopoverLayout.size(mode).height)
        .foregroundStyle(Palette.primary)
        .environment(\.motionReduced, reduceMotion)
        .environment(\.motionActive, active && !preferences.showingSettings && !preferences.showingDevices)
        .overlay(alignment: .bottom) {
            if !compact, let notice = spotify.notice {
                HStack(spacing: 8) {
                    Image(systemName: notice.icon).foregroundStyle(Palette.green)
                    Text(notice.message).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    Spacer(minLength: 3)
                    if let undo = notice.undo { Button("Undo") { undo(); spotify.notice = nil }.buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.green) }
                    Button { spotify.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                }.padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
                    .shadow(color: Palette.shadow, radius: 12, y: 5)
                    .padding(.horizontal, 20).padding(.bottom, 65)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.animation(reduced: reduceMotion), value: spotify.notice?.id)
        .animation(Motion.animation(reduced: reduceMotion), value: preferences.showingSettings)
        .animation(Motion.animation(reduced: reduceMotion), value: preferences.showingDevices)
    }
}

private struct AppHeader: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    let compact: Bool
    @EnvironmentObject private var player: PlayerState
    var body: some View {
        HStack(spacing: 9) {
            ZStack { Circle().fill(Palette.brand.gradient).frame(width: 27, height: 27); PlayingWaveform(playing: player.playback?.is_playing == true, color: Palette.onBrand, width: 15, height: 17) }
            Text("spotmenu").font(.system(size: 18, weight: .heavy, design: .rounded)).tracking(-0.7)
            Spacer()
            if compact, let error = spotify.error { IconButton(icon: spotify.offline ? "wifi.slash" : "exclamationmark.circle", label: error) { preferences.compact = false } }
            if !compact { IconButton(icon: "magnifyingglass", label: "Search · ⌘K") { spotify.closeDetail(); preferences.focusSearch() } }
            if spotify.busy { ProgressView().controlSize(.small).frame(width: 28, height: 28) }
            else { IconButton(icon: "arrow.clockwise", label: "Refresh library") { Task { await spotify.refreshAll() } } }
            IconButton(icon: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", label: compact ? "Expand player" : "Compact player") { preferences.compact = !compact }
            IconButton(icon: "gearshape", label: "Settings") { preferences.showingSettings = true; preferences.compact = false }
        }.padding(.horizontal, 18).padding(.top, 13).padding(.bottom, 12)
    }
}

private struct BrowseArea: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    @FocusState private var searchFocused: Bool
    @Environment(\.motionReduced) private var reduceMotion
    private var browseKey: String { spotify.detailTitle.map { "detail:\($0)" } ?? preferences.tab.rawValue }
    private var scrollAnchor: Binding<String?> {
        Binding(get: { preferences.scrollAnchors[browseKey] }, set: { if let value = $0, preferences.scrollAnchors[browseKey] != value { preferences.scrollAnchors[browseKey] = value } })
    }
    var body: some View {
        VStack(spacing: 0) {
            if let error = spotify.error { RecoveryBanner(message: error).padding(.horizontal, 18).padding(.bottom, 10) }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        if let title = spotify.detailTitle { detailContent(title) }
                        else {
                            switch preferences.tab {
                            case .home: homeContent
                            case .search: searchContent
                            case .library: libraryContent
                            case .queue: queueContent
                            }
                        }
                    }.scrollTargetLayout().frame(maxWidth: .infinity).padding(.horizontal, 18).padding(.bottom, 18)
                }
                .scrollPosition(id: scrollAnchor, anchor: .top)
                .id(browseKey)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                .onChange(of: preferences.selection) { _, index in
                    let entries = preferences.entries(from: spotify.search)
                    if preferences.tab == .search && entries.indices.contains(index) { proxy.scrollTo("search:\(entries[index].id)", anchor: .center) }
                }
            }.animation(Motion.animation(reduced: reduceMotion), value: browseKey)
                .clipped()
        }
        .onChange(of: preferences.focusSearchRequest) { _, _ in searchFocused = true }
        .onChange(of: preferences.query) { _, value in preferences.selection = 0; spotify.searchFor(value) }
        .onChange(of: preferences.searchFilter) { _, _ in preferences.selection = 0 }
        .onChange(of: preferences.tab) { _, tab in
            spotify.closeDetail()
            if tab == .search { searchFocused = true }
        }
        .task(id: preferences.tab) { if preferences.tab == .queue { await spotify.loadQueue() } }
    }
    @ViewBuilder private var homeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR SPACE").font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(Palette.green)
            Text("Good to see you\(spotify.profile?.display_name.map { ", \($0.components(separatedBy: " ").first ?? $0)" } ?? "")")
                .font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(2)
            if spotify.offline { Text("Browsing your cached library").font(.system(size: 10)).foregroundStyle(Palette.muted) }
        }.padding(.bottom, 5).id("home:top")
        if spotify.busy && spotify.playlists.isEmpty && spotify.recent.isEmpty {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading your music…").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 11) { RoundedRectangle(cornerRadius: 8).fill(Palette.raised).frame(width: 42, height: 42); VStack(alignment: .leading, spacing: 8) { RoundedRectangle(cornerRadius: 3).fill(Palette.raised).frame(width: 180, height: 10); RoundedRectangle(cornerRadius: 3).fill(Palette.raised).frame(width: 120, height: 8) }; Spacer() }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            }
        }
        let pinned = spotify.playlists.filter { preferences.pinnedIDs.contains($0.stableID) }
        if !spotify.playlists.isEmpty {
            HStack { SectionLabel(title: pinned.isEmpty ? "Your playlists" : "Pinned for you", icon: pinned.isEmpty ? "square.stack" : "pin.fill"); Spacer(); Button("See all") { preferences.filter = .playlists; preferences.tab = .library }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.green).buttonStyle(.plain) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 11) {
                    ForEach((pinned.isEmpty ? Array(spotify.playlists.prefix(10)) : pinned), id: \.stableID) { playlist in
                        PlaylistTile(playlist: playlist)
                    }
                }.padding(.vertical, 4)
            }.frame(height: 148).id("home:playlists")
        }
        HStack(spacing: 10) {
            Button { preferences.filter = .songs; preferences.tab = .library } label: { Label("Liked songs", systemImage: "heart.fill").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 11)) }
            Button { preferences.tab = .queue; Task { await spotify.loadQueue() } } label: { Label("Your queue", systemImage: "text.line.first.and.arrowtriangle.forward").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 11)) }
        }.buttonStyle(PressStyle()).foregroundStyle(Palette.green)
        if !spotify.recent.isEmpty {
            SectionLabel(title: "Recently played", icon: "clock.arrow.circlepath").padding(.top, 9)
            ForEach(Array(spotify.recent.prefix(6).enumerated()), id: \.offset) { index, track in TrackRow(track: track).id("home:recent:\(index):\(track.stableID)") }
        }
        if !spotify.topTracks.isEmpty {
            SectionLabel(title: "On repeat", icon: "sparkles").padding(.top, 9)
            ForEach(spotify.topTracks.prefix(6), id: \.stableID) { TrackRow(track: $0).id("home:top:\($0.stableID)") }
        }
        if spotify.playlists.isEmpty && spotify.recent.isEmpty && !spotify.busy { EmptyCard(title: "Make yourself at home", text: "Play something in Spotify, or search for a favorite to get started.", icon: "music.note.house") }
    }
    @ViewBuilder private var libraryContent: some View {
        Text("Your library").font(.system(size: 20, weight: .bold, design: .rounded)).id("library:top")
        HStack(spacing: 6) { ForEach(LibraryFilter.allCases, id: \.self) { filter in FilterPill(text: filter.rawValue, selected: preferences.filter == filter) { preferences.filter = filter } } }.padding(.bottom, 4)
        if preferences.filter == .all || preferences.filter == .playlists || preferences.filter == .pinned {
            SectionLabel(title: preferences.filter == .pinned ? "Pinned playlists" : "Playlists", icon: "square.stack")
            let playlists = spotify.playlists.filter { preferences.filter != .pinned || preferences.pinnedIDs.contains($0.stableID) }
            ForEach(playlists, id: \.stableID) { PlaylistRow(playlist: $0).id("library:playlist:\($0.stableID)") }
            if playlists.isEmpty { EmptyCard(title: preferences.filter == .pinned ? "Keep your favorites close" : "No playlists yet", text: "Use the pin beside a playlist to put it on Home.", icon: "pin") }
            if spotify.playlistNext != nil { LoadMoreButton(title: "Load more playlists", loading: spotify.loadingPlaylists) { Task { await spotify.loadMorePlaylists() } }.id("library:morePlaylists") }
        }
        if preferences.filter == .all || preferences.filter == .songs {
            SectionLabel(title: "Liked songs · \(spotify.saved.count) loaded", icon: "heart.fill").padding(.top, 5)
            ForEach(Array(spotify.saved.enumerated()), id: \.element.stableID) { _, track in TrackRow(track: track).id("library:saved:\(track.stableID)") }
            if spotify.saved.isEmpty { EmptyCard(title: "A place for your favorites", text: "Tap the heart on a track to save it here.", icon: "heart") }
            if spotify.savedNext != nil { LoadMoreButton(title: "Load more liked songs", loading: spotify.loadingSaved) { Task { await spotify.loadMoreSaved() } }.id("library:moreSaved") }
        }
    }
    @ViewBuilder private var searchContent: some View {
        Text("Find your next favorite").font(.system(size: 20, weight: .bold, design: .rounded)).id("search:top")
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.green)
            TextField("Songs, artists, albums, playlists", text: $preferences.query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                .onSubmit { activateSelected() }
                .onAppear { searchFocused = true }
            if spotify.searching { ProgressView().controlSize(.small) }
            else if !preferences.query.isEmpty { IconButton(icon: "xmark.circle.fill", label: "Clear search", size: 12) { preferences.query = "" } }
        }.padding(11).background(Palette.raised, in: RoundedRectangle(cornerRadius: 12)).id("search:field")
        if preferences.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !preferences.recentSearches.isEmpty {
                HStack { SectionLabel(title: "Recent searches", icon: "clock"); Spacer(); Button("Clear") { preferences.recentSearches = [] }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                ForEach(preferences.recentSearches, id: \.self) { value in
                    Button { preferences.query = value; searchFocused = true } label: { HStack { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); Text(value); Spacer(); Image(systemName: "arrow.up.left").foregroundStyle(Palette.muted) }.font(.system(size: 12)).padding(11).frame(maxWidth: .infinity).modifier(CardSurface()) }.buttonStyle(PressStyle(scale: 0.985)).id("search:recent:\(value)")
                }
            } else { EmptyCard(title: "All your music, a few keys away", text: "Search Spotify, then use ↑ ↓ and Return to choose a result.", icon: "sparkle.magnifyingglass") }
        } else {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(SearchFilter.allCases, id: \.self) { filter in FilterPill(text: filter.rawValue, selected: preferences.searchFilter == filter) { preferences.searchFilter = filter } } } }
            let entries = preferences.entries(from: spotify.search)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if case .track(let track) = entry { TrackRow(track: track, selected: index == preferences.selection, onPlay: { preferences.rememberSearch(preferences.query) }).id("search:\(entry.id)") }
                else {
                    Button { preferences.rememberSearch(preferences.query); Task { await spotify.activate(entry) } } label: {
                        HStack(spacing: 11) { CoverArt(url: entry.imageURL, size: 42); VStack(alignment: .leading, spacing: 4) { Text(entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); Text(entry.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.muted) }.padding(8).frame(maxWidth: .infinity).modifier(CardSurface(active: index == preferences.selection))
                    }.buttonStyle(PressStyle(scale: 0.985)).id("search:\(entry.id)")
                }
            }
            if !spotify.searching && spotify.search != nil && entries.isEmpty { EmptyCard(title: "No matches here", text: "Try another spelling or a different filter.", icon: "magnifyingglass") }
        }
    }
    private func activateSelected() {
        let entries = preferences.entries(from: spotify.search)
        preferences.rememberSearch(preferences.query)
        if !entries.isEmpty { Task { await spotify.activate(entries[min(preferences.selection, entries.count - 1)]) } }
    }
    @ViewBuilder private var queueContent: some View {
        HStack { Text("Up next").font(.system(size: 20, weight: .bold, design: .rounded)); Spacer(); if spotify.loadingQueue { ProgressView().controlSize(.small) } else { IconButton(icon: "arrow.clockwise", label: "Refresh queue") { Task { await spotify.loadQueue() } } } }.id("queue:top")
        Text("\(spotify.queue.count) tracks ready to go").font(.system(size: 11)).foregroundStyle(Palette.muted)
        ForEach(Array(spotify.queue.enumerated()), id: \.offset) { index, track in TrackRow(track: track, following: Array(spotify.queue.dropFirst(index + 1).prefix(99))).id("queue:\(index):\(track.stableID)") }
        if spotify.queue.isEmpty && !spotify.loadingQueue { EmptyCard(title: "The queue is yours", text: "Use a song's ••• menu to add it to your queue.", icon: "text.badge.plus") }
    }
    @ViewBuilder private func detailContent(_ title: String) -> some View {
        HStack { Button { spotify.closeDetail() } label: { Label("Back", systemImage: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green) }.buttonStyle(.plain); Spacer(); IconButton(icon: "arrow.up.right.square", label: "Open collection in Spotify") { spotify.openSpotify(spotify.detailURI) } }.id("detail:top")
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 21, weight: .bold, design: .rounded)).lineLimit(2); Text("\(spotify.detailTracks.count) tracks loaded").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            Spacer()
            if !spotify.detailTracks.isEmpty { IconButton(icon: "play.fill", label: "Play collection", active: true, size: 21) { Task { await spotify.playCollection() } } }
        }
        if spotify.detailLoading && spotify.detailTracks.isEmpty { HStack { ProgressView().controlSize(.small); Text("Loading your music…").font(.caption).foregroundStyle(Palette.muted) }.padding(.vertical, 15) }
        ForEach(Array(spotify.detailTracks.enumerated()), id: \.offset) { index, track in TrackRow(track: track, contextURI: spotify.detailURI, contextPosition: index).id("detail:\(index):\(track.stableID)") }
        if spotify.detailNext != nil { LoadMoreButton(title: "Load more tracks", loading: spotify.detailLoading) { Task { await spotify.loadMoreDetail() } } }
        if !spotify.detailLoading && spotify.detailTracks.isEmpty { EmptyCard(title: "Open this collection in Spotify", text: "Spotify may limit which playlist contents this app can browse.", icon: "arrow.up.right.square") }
    }
}

private struct PlaylistTile: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    let playlist: Playlist
    @State private var hover = false
    @Environment(\.motionReduced) private var reduceMotion
    var body: some View {
        Button { Task { await spotify.openPlaylist(playlist) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                CoverArt(url: playlist.imageURL, size: 110, radius: 11)
                Text(playlist.name).font(.system(size: 11, weight: .semibold)).lineLimit(2).frame(width: 110, alignment: .leading)
            }.offset(y: hover && !reduceMotion ? -3 : 0)
                .shadow(color: hover ? Palette.shadow : .clear, radius: 10, y: 5)
        }.buttonStyle(PressStyle(scale: 0.96)).onHover { hover = $0 }
            .animation(Motion.animation(reduced: reduceMotion), value: hover)
            .contextMenu { Button(preferences.pinnedIDs.contains(playlist.stableID) ? "Unpin playlist" : "Pin playlist", systemImage: "pin") { preferences.togglePin(playlist) }; Button("Open in Spotify", systemImage: "arrow.up.right.square") { spotify.openSpotify(playlist.uri) } }
    }
}

private struct AppTabBar: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.motionReduced) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = preferences.tab == tab
                Button {
                    withAnimation(Motion.animation(reduced: reduceMotion)) { preferences.tab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 15, weight: .semibold))
                            .modifier(SymbolFeedback(trigger: selected ? 1 : 0))
                        Text(tab.rawValue).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Palette.green : Palette.muted)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background {
                        if selected {
                            if reduceMotion { RoundedRectangle(cornerRadius: 11).fill(Palette.green.opacity(0.12)) }
                            else { RoundedRectangle(cornerRadius: 11).fill(Palette.green.opacity(0.12)).matchedGeometryEffect(id: "selection", in: selection) }
                        }
                    }
                }.buttonStyle(PressStyle(scale: 0.96)).help(tab.rawValue)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        .animation(Motion.animation(reduced: reduceMotion), value: preferences.tab)
    }
}

private struct RecoveryBanner: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) { Image(systemName: spotify.offline ? "wifi.slash" : "exclamationmark.circle"); Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0); Button { spotify.dismissError() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain) }
            Button(actionTitle) {
                switch spotify.recovery {
                case .reconnect: spotify.connect()
                case .device: preferences.showingDevices = true; Task { await spotify.loadDevices() }
                case .retry, .wait: Task { await spotify.refreshAll() }
                }
            }.buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.green)
        }.padding(10).foregroundStyle(Palette.muted).background(Palette.raised, in: RoundedRectangle(cornerRadius: 11))
    }
    private var actionTitle: String { switch spotify.recovery { case .retry: "Retry"; case .reconnect: "Reconnect Spotify"; case .device: "Choose a device"; case .wait: "Try again" } }
}

private struct OnboardingView: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        VStack(spacing: 15) {
            HStack { Spacer(); IconButton(icon: "gearshape", label: "Settings") { preferences.showingSettings = true } }
            Spacer()
            ZStack { Circle().fill(Palette.green.opacity(0.17)).frame(width: 165).blur(radius: 28); Circle().fill(Palette.brand.gradient).frame(width: 92); PlayingWaveform(playing: spotify.connecting, color: Palette.onBrand, width: 42, height: 49) }.frame(height: 150)
            Text("Your music.\nOne click away.").font(.system(size: 33, weight: .heavy, design: .rounded)).tracking(-1.2).multilineTextAlignment(.center)
            Text("A little home for Spotify in your menu bar.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text("SPOTIFY CLIENT ID").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.green)
                TextField("Paste your Spotify app Client ID", text: $spotify.clientID).textFieldStyle(.plain).padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 11))
                Text("Add http://127.0.0.1/callback (without a port) to your developer app's redirect URIs.").font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 17)
            Button { spotify.connect() } label: { HStack { if spotify.connecting { ProgressView().controlSize(.small) }; Text(spotify.connecting ? "Connecting…" : "Connect Spotify"); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onAccent).frame(maxWidth: .infinity).padding(14).background(Palette.green, in: Capsule()) }.buttonStyle(PressStyle()).disabled(spotify.connecting)
            if spotify.connecting { Button("Cancel") { spotify.cancelConnection() }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.muted) }
            if let error = spotify.error { Text(error).font(.system(size: 11)).foregroundStyle(.red.opacity(0.85)).multilineTextAlignment(.center) }
            Button("Open Spotify Developer Dashboard") { NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Spacer()
            Text("Music plays on your Spotify devices").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(32)
    }
}

struct Sheet<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(title).font(.system(size: 23, weight: .bold, design: .rounded)); Spacer(); IconButton(icon: "xmark", label: "Close · Escape", action: close) }
            content()
            Spacer(minLength: 0)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.ink)
    }
}
private struct DevicesView: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var player: PlayerState
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        Sheet(title: "Connect to a device", close: { preferences.showingDevices = false }) {
            HStack { Text("Your music, wherever you are").font(.system(size: 12)).foregroundStyle(Palette.muted); Spacer(); if spotify.loadingDevices { ProgressView().controlSize(.small) } else { IconButton(icon: "arrow.clockwise", label: "Refresh devices") { Task { await spotify.loadDevices() } } } }
            if let error = spotify.error { RecoveryBanner(message: error) }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
            ForEach(spotify.devices, id: \.stableID) { device in
                Button { Task { await spotify.transfer(to: device) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(device.type)).font(.system(size: 21)).frame(width: 30).foregroundStyle(device.is_active ? Palette.green : Palette.muted)
                        VStack(alignment: .leading, spacing: 4) { Text(device.name).font(.system(size: 13, weight: .semibold)); Text(device.is_restricted == true ? "Control unavailable" : device.is_active ? "Currently playing here" : device.type).font(.system(size: 11)).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity, alignment: .leading)
                        if player.transferringID == device.id { ProgressView().controlSize(.small) }
                        else if device.is_active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green) }
                    }.padding(13).frame(maxWidth: .infinity).modifier(CardSurface(active: device.is_active))
                }.buttonStyle(PressStyle(scale: 0.97)).disabled(player.transferringID != nil || device.is_restricted == true || device.id == nil)
            }
            if spotify.devices.isEmpty && !spotify.loadingDevices {
                EmptyCard(title: "Wake up a Spotify device", text: "Open Spotify on your Mac, phone, or speaker, then refresh this list.", icon: "hifispeaker.and.homepod")
                Button("Open Spotify on this Mac") { NSWorkspace.shared.open(URL(string: "spotify:")!) }.buttonStyle(.plain).foregroundStyle(Palette.green)
            }
                }
            }
        }
    }
    private func icon(_ type: String) -> String { switch type.lowercased() { case "computer": "laptopcomputer"; case "smartphone": "iphone"; default: "hifispeaker" } }
}
