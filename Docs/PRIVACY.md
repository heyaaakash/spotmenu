# Privacy and removal

This describes the current source. It is an implementation review, not a captured network audit or a promise about Spotify’s own data handling.

| Data | Stored or sent | Retention / removal |
| --- | --- | --- |
| Spotify refresh token | macOS Keychain, service `com.spotmenu.auth`, account `refreshToken` | Removed by **Disconnect Spotify** |
| Access token and PKCE verifier/state | Process memory; sent directly to Spotify authorization/API endpoints | Replaced on refresh or cleared on disconnect/process exit |
| Client ID | User defaults; sent to Spotify authorization/token endpoints | Remains after disconnect; it is an app identifier, not a client secret |
| Appearance, waveform audio opt-in, player mode, volume, selected tab, filters, pins, scroll positions | Local user defaults | Remain after disconnect |
| Up to eight recent search terms | User defaults; searches are sent to Spotify | Clear in Settings or disable **Remember recent searches** |
| Profile display name, playlists, saved/recent/top tracks, paging links and saved IDs | `~/Library/Application Support/SpotMenu/library.json` | Snapshot refreshed during use; removed asynchronously on disconnect |
| Album/playlist images | Memory and `~/Library/Caches/SpotMenu/Artwork`; downloaded from URLs Spotify returns | Roughly 30 MB memory budget and 50 MB disk trimming target; disk trimming is periodic, not a hard limit |
| Spotify desktop playback broadcasts | Track title/artist/album, Spotify URI, duration, position and playing state received locally; bounded and validated before temporary display | Memory only; reconciled with the Web API and cleared on disconnect/process exit |
| Player/device state and queue | Memory; device IDs and actions sent to Spotify when used | Cleared on disconnect/process exit |
| Spotify desktop audio (optional) | Spotify-only Core Audio process tap; samples analyzed in memory for spectrum, waveform peaks, and bass onsets | Off by default; requires macOS permission and an enabled setting. Samples are not recorded, written to disk, sent to Spotify, or uploaded. Capture stops when the player is hidden/paused or motion is reduced. No microphone or other apps are captured. |
| Popover timing | macOS OSLog, subsystem `com.spotmenu.app`, category `Responsiveness` | OS-managed retention; current logging records operation names and durations |

The app uses `accounts.spotify.com` for authorization/tokens, `api.spotify.com` for Web API requests, and image endpoints supplied by Spotify for artwork. Links may open `open.spotify.com` or Spotify support in your browser. The callback listener uses a temporary local IPv4 loopback port while connecting. Playback detection uses local desktop notifications plus background API polling; notifications do not request Automation or audio-capture permission. Desktop fallback uses `osascript` to send local Apple Events to Spotify, with an eight-second timeout.

There is no application-owned telemetry, advertising, or remote crash-reporting service in the source. Spotify and your browser/OS may keep their own records. Avoid sending tokens, Client IDs, raw authorization callbacks, private playlist contents, or personal device names in issue reports.

## Disconnect or uninstall

1. Choose **Disconnect Spotify** before quitting to remove the token and library snapshot. This does not revoke the app’s access at Spotify.
2. If desired, remove the developer app’s access through your Spotify account settings.
3. Quit SpotMenu and remove `SpotMenu.app` from Applications.
4. For a full local cleanup, remove the `SpotMenu` folders under `~/Library/Application Support` and `~/Library/Caches`, and the `com.spotmenu.app` preferences using macOS tools. If you removed the app before disconnecting, remove its `com.spotmenu.auth` refresh-token entry in Keychain Access.

Uninstalling the bundle alone leaves local preferences, caches, and Keychain data. No upgrade/downgrade migration or automatic update mechanism has been validated for a published release yet.
