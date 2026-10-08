# Changelog

Version metadata comes from `VERSION` and `BUILD_NUMBER`. Future immutable release tags use `vMAJOR.MINOR.PATCH`.

## Unreleased

- (none)

## 1.4.4 — 2026-10-08

- Spotify sign-in selects an available local callback port, preventing another app using port 8888 from blocking connection or reconnection.
- Spotify authorization opens only after the new callback listener reaches its ready state; stale sign-in attempts cannot launch a browser.
- Liked Songs starts the selected track from its album at the track URI offset instead of sending up to 100 liked-song URIs as a playback list.
- Queue selections retain their ordered following tracks; the continuation setting copy now reflects this behavior.
- Group app output by version and type: architecture-specific bundles, working packages, and verified release snapshots. Keep launch media in `dist/media/` and other non-release deliverables in `dist/other/`, separate from release versions. Build, packaging, and draft-upload scripts share the same paths; isolated builds can use an alternate output root.

## 1.4.3 — 2026-10-01

- Automatic playback detection continues while the menu is closed, keeping the menu bar playing indicator current.
- Spotify desktop playback notifications update track/play/pause state immediately on receipt, followed by a Web API reconciliation. Briefly stale or empty responses cannot erase a newer desktop event.
- Backup polling checks every two seconds while the menu is open, and every five/ten seconds in the background for playing/idle states. Opening the menu, waking the Mac, Spotify launch/quit, and network restoration request an early check.
- Playback detection no longer waits for liked-song status requests. Dynamic API reads bypass the local HTTP cache.
- Network failures retry with bounded backoff; notification bursts coalesce and Spotify Retry-After limits remain respected. Disconnect clears pending requests and retry state.

## 1.4.2

- Replaced GitHub Actions with local verification, screenshot generation, arm64/x86_64 packaging, checksums, and an explicit draft-release upload script.

- Smooth, broad crests travel continuously instead of reshaping from each PCM snapshot.
- Audio loudness controls a gently interpolated amplitude envelope; rapid audio fluctuations no longer shake the wave surface.
- The small waveform renders at up to 60 frames per second while visible and playing. Capture remains capped at 30 frames per second.
- Wave motion remains continuous across clock-hour boundaries and stops with the existing visibility, pause, and Reduce Motion gates.

## 1.4.1

- One layered, filled waveform integrated with the song’s seek rail, clipped to elapsed playback.
- Removed the separate visualizer panel, spectrum choice, intensity slider, and extra visualization actions.
- Music visuals has only the audio-reactive toggle; existing appearance and playback settings remain available.
- Wave motion stops for paused/hidden players, disabled animations, and Reduce Motion.
- Seek position appears immediately on menu opening and track changes, without sliding from zero.

## 1.4.0

- Optional Spotify-only local audio visualization using Core Audio process taps on macOS 14.2+.
- Spectrum and waveform styles, adjustable intensity, and artwork pulses driven by detected bass onsets.
- Explicit opt-in and macOS audio-capture permission; no audio recording, storage, microphone input, or upload.
- Capture stops when music pauses, the menu closes, Settings/Devices obscure the player, or Reduce Motion is enabled.
- Capture errors remain visible in Settings with a retry action, and clear after successful recovery.
- Decorative fallback is labeled separately for remote devices, denied/unavailable audio, and older macOS versions.
- Live capture, permission flows, and beat alignment require manual validation; synthetic DSP and mocked lifecycle checks are separate evidence.

## 1.3.0

- Compact and expanded players with playback controls and device selection.
- Home, search, library, liked songs, queue, paging, and pinned playlists.
- Optimistic feedback, ordered commands, rollback, and Undo for saved songs.
- Local library/artwork caching and specific offline/session/device/rate-limit recovery.
- Persisted preferences, Light/Dark/Auto appearance, Reduce Motion, and in-menu Settings.
- Album/playlist-context continuation, with ordered loaded-song continuation for liked songs and queue.
- Standalone repository with native sample-data screenshots, focused docs, support templates, and macOS CI.
- Repeatable ad-hoc app/ZIP packaging, checksum generation, and archive verification.

This version is source-available in the repository; it is not a published binary release. Live Spotify behavior, clean installation, minimum-macOS compatibility, signing trust, and Intel hardware remain separate validation work.
