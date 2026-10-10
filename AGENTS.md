# Repository instructions

- Use `./Scripts/test.sh` for the existing isolated regression harness. Do not substitute `swift test`: this project uses a standalone native harness rather than an XCTest target.
- GitHub Actions is disabled. Do not add workflows; use `./Scripts/verify.sh` and `./Scripts/prepare-release.sh` for local verification and release preparation. Cross-compilation does not prove runtime support on the target Mac.
- Use `./Scripts/package.sh` for release packaging. App builds, packages, and release snapshots belong in `dist/<version>/`, not `.build/`. Source `Scripts/dist-paths.sh` for shared paths: `apps/<architecture>/PlayMenu.app`, `packages/`, and `release/`. Brag/video projects belong in `dist/media/<project>/`; other non-release deliverables belong in `dist/other/<task>/`. Never place promotional or unrelated output inside a release version or release upload; `PLAYMENU_DIST_ROOT` (also accepts the previous `SPOTMENU_DIST_ROOT`) selects an isolated output root.
- `VERSION` and `BUILD_NUMBER` supply bundle metadata. Settings reads the app bundle version. Keep release notes and tags aligned with those files.
- Generated icons come from `Resources/AppIcon.png`; do not track `Resources/PlayMenu.iconset`, `Resources/PlayMenu.icns`, `.build`, or `dist`.
- Preserve command ordering, optimistic rollback, stale-session guards, PKCE state checks, Keychain storage, and the local-only OAuth callback.
- Test and screenshot fixtures must not use a real Spotify account, network API, or Keychain. Screenshot previews use native views with fictional data and locally drawn artwork; label them accordingly.
- Preserve accessibility labels, Reduce Motion, Auto/Light/Dark, fixed compact/expanded sizes, and menu-only Settings.
- Build/test scripts honor `SDKROOT`. If sandboxed `iconutil` rejects a valid icon set, rerun with the required macOS tool access; do not treat old build output as proof of a fresh build.
- Current signing is ad-hoc, without Developer ID or notarization. Never call it Apple verified.
- Keep the README concise and user-oriented. Detailed API, development, privacy, compatibility, and release material belongs in `Docs/`.
- Do not describe build success, mocked tests, fixture renders, or CI as live Spotify or clean-install validation. Keep `Docs/CAPABILITY_MATRIX.md` current.
