# Features and keyboard shortcuts

These features are implemented. Automated checks and live validation are recorded separately in the [capability matrix](CAPABILITY_MATRIX.md).

## The experience

- **Two player sizes:** a 432 × 140 compact player and a 432 × 690 expanded menu. Separate fixed hosting controllers and cancellable transition tokens prevent stale resize/reopen work from moving the content.
- **A persistent player:** playback, seek, volume, shuffle, repeat, hearts, and device selection stay above Home, Search, Library, and Queue.
- **Immediate controls:** playback and hearts update locally before a request finishes. Commands are sent in order; failures restore the affected control without erasing other changes. Saved-song changes include an Undo toast.
- **A populated launch:** playlists, liked songs, recent tracks, and top tracks load from a disk snapshot, then refresh concurrently. Album artwork uses a memory cache, a disk cache, coalesced downloads, and thumbnails sized for the display.
- **A fuller library:** pin favorite playlists to Home, filter playlists and liked songs, and load additional library and collection pages. Collection play buttons start the playlist or album context.
- **Search:** a 220 ms debounce, cancellation of stale results, type filters, eight recent searches, and keyboard selection.
- **Clear recovery:** cached content stays available when offline; expired sessions, unavailable devices, and rate limits get specific recovery actions. Device transfers show progress. Compact mode exposes an error indicator that opens the full recovery view.
- **Remembered preferences:** player size, selected tab, library filter, pins, browsing position, recent searches, and volume survive relaunches.
- **Appearance & settings:** choose Auto, Light, or Dark in the scrollable in-menu Settings panel. Auto follows macOS immediately. Persisted options control animations, continuation for individual song selections, desktop playback fallback, recent-search history, and the menu bar playing indicator. Reduce Motion is always respected. Settings has no separate window to open or restore at launch.
- **Motion:** spring presses and hover lift, bouncing SF Symbols, morphing play/pause, a sliding tab selection pill, collection transitions, sliding sheets, and spring toasts. The Now Playing artwork lifts when playing; five equalizer bars animate smoothly over a softly moving player glow.
- **Music controls:** iPhone-inspired scrubbers expand their track and thumb while interacting and move smoothly during playback. Drag changes stay local until release; keyboard and accessibility adjustments are supported.
- **Native details:** full-width rows, bounded playlist tiles, current-track states, and accessible control labels. Device lists scroll within the menu. Reduce Motion replaces springs with short fades and freezes decorative playback animations.

Playback monitoring runs for the app’s lifetime. Spotify desktop notifications provide prompt track/play/pause updates on receipt. Backup API checks run every two seconds while the menu is open, every five seconds while playing in the background, and every ten seconds when idle in the background. Failures back off, and rate limits take priority. The visual progress timer runs only while the menu is open. Continuous visual animations stop when the menu is closed, their player mode is hidden, music is paused, or Reduce Motion is enabled. Player animations also stop behind Settings and Devices. By default, equalizer bars reflect playback state. With local audio capture enabled, the progress-bar waveform, small player indicators, and artwork pulses react to measured Spotify audio; header and list indicators remain decorative. Audio analysis runs on a dedicated serial queue, with capture frames capped at 30 per second. Only the small waveform draws at up to 60 frames per second while active. Artwork processing, cache I/O, JSON decoding, and local Spotify Automation run away from the UI thread. Popover presentation timing is recorded through OSLog under subsystem `com.playmenu.app`, category `Responsiveness`.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⇧Space | Open or close PlayMenu globally |
| ⌘K | Expand and focus Search |
| ⌘, | Open Settings in the expanded menu |
| ↑ / ↓ | Select a search result |
| Return | Play a song or open a collection |
| Space | Play/pause when not typing |
| Escape | Close an overlay, return from a collection, or dismiss the menu |

If another app has claimed ⌘⇧Space, PlayMenu reports that the shortcut is unavailable.

## Music visuals

The expanded player has one waveform design: three soft, translucent filled waves rise directly from the seek rail and are clipped to the elapsed part of the song. The white thumb, drag seeking, keyboard adjustments, and elapsed/total times remain accessible. Paused playback, hidden players, disabled animations, and Reduce Motion flatten the waves.

Settings → Music visuals contains just **Audio-reactive waveform**, off by default. There are no style or intensity controls. When enabled, a private [Core Audio process tap](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) samples only Spotify desktop audio on this Mac (macOS 14.2+ and macOS audio-capture permission required). Measured loudness and bass onsets feed a smooth amplitude envelope while broad crests travel continuously; artwork pulses use detected bass onsets. These pulses are an onset heuristic, not a BPM estimate or guaranteed beat grid.

When fresh measured frames are unavailable, the waves animate decoratively. Settings and the seek control’s accessibility hint explain that distinction without adding a panel or badges to the player. Capture stops for closed menus, paused music, obscured players, disabled animations, and Reduce Motion. Samples remain in memory and are never recorded or uploaded. Capture errors remain visible in Settings; closing Settings or toggling the option off/on retries when playback is active. See [privacy](PRIVACY.md) and the [capability matrix](CAPABILITY_MATRIX.md) for validation limits.
