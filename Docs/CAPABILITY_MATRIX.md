# Capability and validation matrix

Source version: **1.4.4**. This matrix separates implementation, automated checks, and live use. Build or fixture-render success does not establish sign-in, Premium eligibility, real playback, clean installation, or accessibility on every supported Mac.

## Environments

| Environment | Evidence and limit |
| --- | --- |
| Apple Silicon — 1.4.4 build 10 | Replacement package compiled and packaged locally; Liked Songs behavior has not been regression-tested or live-verified. See [validation](VALIDATION.md). |
| Apple Silicon, macOS 27.0.1 — 1.4.3 local | `./Scripts/test.sh` passed all 46 checks on 2026-10-01, including desktop event validation, closed-menu monitoring, queued refreshes, recovery, rate limits, audio analysis, and native view fixtures. Real desktop broadcasts, live sign-in/playback/audio capture, and permission prompts remain unverified. |
| Apple Silicon, macOS 27.0.1 — 1.3.0 | Existing 30-check harness passed on 2026-09-30 after repository extraction. Presentation/build validation is recorded in [VALIDATION.md](VALIDATION.md). |
| Historical 1.3.0 hosted checks | Previous Apple Silicon and Intel results are retained in [VALIDATION.md](VALIDATION.md). GitHub Actions is now disabled. |
| macOS 14 minimum | Declared in `Package.swift` and the app plist. No clean installation or real-user journey recorded here. |
| Intel Mac — 1.4.4 build 10 | x86_64 release binary cross-compiled locally; ZIP extraction, architecture, plist, signature, bundled license, and SHA-256 verified. Physical Intel runtime is unverified. |
| Other macOS releases | No complete version/device matrix recorded. |

## Features

Historical 1.3.0 hosted evidence predates the optional audio visualizer. Current audio checks are local synthetic/mocked evidence only.

The 1.4.4 build 10 OAuth and Liked Songs fixes compile and package locally; the regression harness and live Spotify verification were not performed for build 10. All rows below describe implemented behavior unless marked unsupported. Live Spotify sign-in and playback are **unverified in this release-preparation record**.

| Feature | Automated evidence | Limits / live validation |
| --- | --- | --- |
| Compact and expanded players | Native size fixtures; 100 transition/dismissal sequences; appearance changes | Real popover animation and menu-bar interaction need live checks |
| Automatic playback detection | Ten regressions: immediate synthetic desktop event updates, malformed metadata, remote/command guards, stale and 204 responses, slow saved lookups, closed-menu polling, queued hints, menu wake/monitor stop/restart, network recovery, rate limits, disconnect cancellation | Real Spotify broadcasts and end-to-end detection latency are unverified. Remote/browser playback uses API polling; desktop events are best-effort. |
| Playback, seek, volume, shuffle, repeat | Mocked optimistic updates, command ordering, rollback, slider clamping | Needs Premium, an active Spotify device, and live playback checks |
| Liked songs, Undo | Current save/check endpoints, rapid heart changes, rollback, stale-check handling | Account permissions and live library changes need checking |
| Home and library | Paging/deduplication, snapshot restoration, preferences | Contents depend on Spotify app quota mode and access |
| Search | Debounce, cancellation, stale-result protection | Results and live account restrictions need checking; no search-result pagination |
| Queue / context continuation | Album/playlist offsets and ordered URI continuation | Liked Songs starts the selected track at its album URI offset; Queue continuation contains up to 99 following loaded tracks |
| Device transfer | Mocked transfer progress and refresh | Real hardware availability, transfer, and restrictions need checking |
| PKCE and Keychain | Source reviewed; no live authorization test recorded | Browser denial, callback port conflict, token persistence, and reconnect need real-account testing |
| Desktop Spotify fallback | Disabled-fallback error path is tested | Real Automation allow/deny prompts and Apple Events need testing; basic controls only |
| Offline and rate limits | Mocked errors, retained metadata, suppressed repeated requests | Offline browsing does not provide offline Spotify playback |
| Settings and appearance | Persistence, Light/Dark/Auto, dynamic colors, contrast checks | Manual VoiceOver, keyboard-only journey, and performance testing remain open |
| Motion and artwork | Existing lifecycle gates, bounded decorative equalizer levels, image downsampling | Header and list indicators remain decorative; player indicators and the progress waveform use live audio only when fresh measured frames arrive |
| Spotify local audio visualizer | Synthetic PCM frequency, RMS, silence, invalid-input and onset tests; mocked capture lifecycle/stale callback tests; native fixture layout | Opt-in Core Audio process tap, Spotify desktop only, macOS 14.2+, and audio-capture permission. Actual capture, allow/deny and recovery flow, physical output devices and perceptual beat alignment remain unverified. No BPM or guaranteed musical beat grid. |

## Unsupported

Windows, Linux, mobile app distribution, browser/VS Code extensions, local audio streaming, changing Spotify Autoplay, native Song Radio/recommendations, automatic app updates, Developer ID signing, and notarization are not provided by this release setup. Spotify audio still comes from the existing playback device.

## Recording new validation

Add the source version/commit, date, macOS version, architecture, Spotify app/account mode, method, result, and evidence. Distinguish mocked checks, native fixture rendering, CI, a clean installation, and external user reports. Remove or qualify public claims when Spotify API behavior changes.
