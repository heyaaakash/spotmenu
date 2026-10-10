# PlayMenu 1.4.4 — build 13

PlayMenu is the new name for the macOS Spotify menu-bar app previously released as SpotMenu. This replacement keeps version 1.4.4 as requested. The existing app bundle identifier and local data locations are retained so existing Spotify sign-in, preferences, permissions, and cached library data continue to work.

## Downloads

- [Apple Silicon ZIP](https://github.com/heyaaakash/playmenu/releases/download/v1.4.4/PlayMenu-1.4.4-macos-arm64.zip)
- [Intel ZIP](https://github.com/heyaaakash/playmenu/releases/download/v1.4.4/PlayMenu-1.4.4-macos-x86_64.zip)
- [SHA-256 checksums](https://github.com/heyaaakash/playmenu/releases/download/v1.4.4/SHA256SUMS.txt)
- [Build provenance](https://github.com/heyaaakash/playmenu/releases/download/v1.4.4/BUILD_INFO.txt)

Quit the old SpotMenu copy before moving `PlayMenu.app` to Applications. The bundle identity is deliberately retained to preserve existing macOS permissions and preferences.

## Changes

- Renamed the app, menu-bar controls, settings, app bundle, executable, icon resources, package names, screenshots, and current project documentation to PlayMenu.
- Added a menu-bar secondary-click menu for quick playback, appearance, settings, and quit actions.
- Hardened liked-song starts and previous/next/play controls against relinked tracks, shuffle failures, stale playback reads, and ambiguous API responses.
- Kept the Spotify Keychain service and local data folders compatible with existing installations.

Packages are ad-hoc signed and not notarized. Intel is cross-compiled; physical Intel runtime remains unverified.
