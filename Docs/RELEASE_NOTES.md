# SpotMenu 1.4.4

A native macOS menu bar companion for Spotify. This replacement release is build **10**.

## Downloads

- [Apple Silicon ZIP](https://github.com/heyaaakash/spotmenu/releases/download/v1.4.4/SpotMenu-1.4.4-macos-arm64.zip)
- [Intel ZIP](https://github.com/heyaaakash/spotmenu/releases/download/v1.4.4/SpotMenu-1.4.4-macos-x86_64.zip)
- [SHA-256 checksums](https://github.com/heyaaakash/spotmenu/releases/download/v1.4.4/SHA256SUMS.txt)
- [Build provenance](https://github.com/heyaaakash/spotmenu/releases/download/v1.4.4/BUILD_INFO.txt)

Unzip the package and move `SpotMenu.app` to Applications. Quit an older running copy before replacing it.

## Fixes

- Spotify sign-in chooses an available local callback port. Register `http://127.0.0.1/callback` without a port in the Spotify Developer Dashboard.
- Selecting a song in Liked Songs starts with that song, then follows the next loaded liked tracks. SpotMenu temporarily holds Shuffle off until Spotify confirms the selected track, restores the previous Shuffle setting, and retries the selected URI alone if Spotify reports a different track. No Spotify playlist is created or modified.
- Queue selections retain their following loaded tracks in order.

## Requirements and limits

- macOS 14 or newer and an eligible Spotify account with an active playback device. Spotify availability and device state can affect playback.
- Liked Songs continuation includes up to 99 following tracks already loaded in SpotMenu.
- The regression harness and live Spotify playback were not verified for build 10. Intel is cross-compiled; physical Intel runtime is unverified. Packages are ad-hoc signed and not notarized.

See the [setup guide](https://github.com/heyaaakash/spotmenu/blob/v1.4.4/Docs/SETUP.md), [validation record](https://github.com/heyaaakash/spotmenu/blob/v1.4.4/Docs/VALIDATION.md), and [changelog](https://github.com/heyaaakash/spotmenu/blob/v1.4.4/CHANGELOG.md).
