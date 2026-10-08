# SpotMenu 1.4.4

A native macOS menu bar companion for Spotify. This release is build **9**.

## Downloads

- [Apple Silicon ZIP](https://github.com/heyaaakash/spotify-mac-menu/releases/download/v1.4.4/SpotMenu-1.4.4-macos-arm64.zip)
- [Intel ZIP](https://github.com/heyaaakash/spotify-mac-menu/releases/download/v1.4.4/SpotMenu-1.4.4-macos-x86_64.zip)
- [SHA-256 checksums](https://github.com/heyaaakash/spotify-mac-menu/releases/download/v1.4.4/SHA256SUMS.txt)
- [Build provenance](https://github.com/heyaaakash/spotify-mac-menu/releases/download/v1.4.4/BUILD_INFO.txt)

Unzip the package and move `SpotMenu.app` to Applications. Quit an older running copy before replacing it.

## Fixes

- Spotify sign-in now chooses an available local callback port, so another app using port 8888 no longer blocks connection or reconnection. Register `http://127.0.0.1/callback` without a port in the Spotify Developer Dashboard.
- Selecting a track in Liked Songs starts that track using its album context and track URI offset. SpotMenu no longer sends the selected song together with up to 99 following liked songs in one request, which could cause Spotify to skip to another item.
- Queue selections continue to include following loaded tracks in order.

## Requirements and limits

- macOS 14 or newer and an eligible Spotify account with an active playback device. Spotify account, device, and track availability can affect playback.
- Both packages are ad-hoc signed and not notarized. Intel is cross-compiled; physical Intel runtime and clean-install behavior have not been verified.
- The local build and package checks passed. The regression harness, live Spotify OAuth, and real liked-song playback were not verified for this release.

See the [setup guide](https://github.com/heyaaakash/spotify-mac-menu/blob/v1.4.4/Docs/SETUP.md), [validation record](https://github.com/heyaaakash/spotify-mac-menu/blob/v1.4.4/Docs/VALIDATION.md), and [changelog](https://github.com/heyaaakash/spotify-mac-menu/blob/v1.4.4/CHANGELOG.md).
