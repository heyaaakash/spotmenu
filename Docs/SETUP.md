# Connect Spotify and troubleshoot

## Before connecting

Use a Spotify account eligible for your developer app. New development-mode app owners need an active Premium subscription, and their app has a restricted user allowance. Playback-control endpoints also require Premium. Spotify changes these rules; check its [development-mode migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide) and [playback endpoint documentation](https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback) before relying on an account or app configuration.

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create an app.
2. Add `http://127.0.0.1/callback` to the app’s redirect URIs. Leave off the port; PlayMenu chooses an available local port for each sign-in.
3. Launch `PlayMenu.app` and paste the Client ID. Do not paste a client secret.
4. Select **Connect Spotify**, approve the browser permission prompt, and return to the menu.
5. Start playback in Spotify and choose the active device in PlayMenu if needed.

Authorization uses PKCE with a temporary callback listener bound to IPv4 loopback on an available port and a checked state value. The refresh token goes into Keychain. Sign-in is a live-account step and is not exercised by the mocked regression suite.

## Requested access

| Spotify scopes | Why PlayMenu requests them |
| --- | --- |
| `user-read-playback-state`, `user-read-currently-playing` | Read the player, current track, and available devices |
| `user-modify-playback-state` | Play/pause, seek, skip, volume, shuffle/repeat, queue additions, and device transfers |
| `user-library-read`, `user-library-modify` | Show liked songs, check hearts, and save/remove songs |
| `playlist-read-private`, `playlist-read-collaborative` | Browse playlists your account can access |
| `user-read-recently-played`, `user-top-read` | Show recent tracks and top tracks |

## Common problems

| What you see | What to try |
| --- | --- |
| Spotify reports a redirect URI mismatch | Register `http://127.0.0.1/callback` without a port in the Spotify Developer Dashboard, then retry. |
| Sign-in canceled or state mismatch | Start a new connection. Verify the exact redirect URI. |
| Session expired | Reconnect from the recovery banner or Settings. |
| Spotify denied an action | Check Premium, the developer app’s access allowance, and the endpoint’s restrictions. |
| No active device | Open Spotify and play a track first, then open the device chooser. |
| Playlist contents missing | Development-mode apps may receive contents only for playlists you own or collaborate on. Open other collections in Spotify. |
| Offline or rate limited | Keep browsing cached metadata; reconnect or wait for the indicated retry time. Playback and new searches need Spotify access. |
| Desktop fallback does not work | Install/open Spotify, enable the fallback in Settings, and check macOS **Privacy & Security → Automation**. The fallback only covers basic player commands. |
| Global shortcut unavailable | Another app may have claimed ⌘⇧Space. Click the music-note menu bar icon instead. |

PlayMenu has no built-in audio engine, Song Radio generator, or control for Spotify’s own Autoplay setting. Enable Autoplay in Spotify on the playback device if you want recommendations after a collection. See [continuation behavior](DEVELOPMENT.md#continuous-playback).
