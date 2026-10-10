# Assets and dependencies

- SwiftUI, AppKit, Foundation, Combine, CryptoKit, Network, Security, ImageIO, UniformTypeIdentifiers, and Carbon are Apple SDK frameworks. SF Symbols are rendered through the platform APIs in the native app.
- No third-party Swift package dependencies are declared in `Package.swift`; there is no dependency lockfile to maintain.
- `Resources/AppIcon.png` is the existing project icon supplied with PlayMenu. Its original source/provenance is not documented in this repository; the owner should confirm publication rights before making a public release.
- Documentation screenshots render the actual app views with fictional track, artist, profile, and device data. Abstract artwork is drawn by `Tests/PlayMenuTests/ScreenshotRenderer.swift`; it is not Spotify album artwork and is not downloaded from another service.
- Spotify is a third-party service. Spotify names and marks belong to their respective owners; PlayMenu is unofficial and has no claimed affiliation or endorsement. Spotify’s own API/content terms apply to live use.

The project code uses the [MIT license](../LICENSE), selected with the owner’s authorization. The inspected source has no third-party package dependencies or imported copyleft implementation. This permits reuse while retaining the copyright and license notice. Third-party service/asset rights are separate. A license does not establish permission to redistribute third-party album artwork or private user data.
