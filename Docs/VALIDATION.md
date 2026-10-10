# Validation record

## 1.4.4 replacement release — build 10

Published on **2026-10-09**, Asia/Kolkata, as the [latest GitHub release](https://github.com/heyaaakash/playmenu/releases/tag/v1.4.4). Annotated tag `v1.4.4` points to clean release commit `29aded577679e74d0aab62b647d97e9e71e26762`. GitHub Actions was not used.

- Both arm64 and x86_64 packages built from the clean release commit. Bundle version/build, architecture, plist, ad-hoc signature, archive contents, extracted executable equality, and checksums passed. Intel is cross-compiled; physical Intel runtime is unverified.
- All five published assets (both ZIPs, `SHA256SUMS.txt`, `BUILD_INFO.txt`, and `RELEASE_NOTES.md`) were downloaded from GitHub and matched byte-for-byte with the local release snapshot. The downloaded ZIPs passed the published SHA-256 manifest.
- ZIP SHA-256: arm64 `5e0b1d76d840da5b3bb51cc4b103e694a92b24622ef22b63e5701d0d67f0b301`; x86_64 `e4505800786e92987862304153a92e005e3196c84b304790f0dc06891f27aa87`.
- The regression harness and live Spotify playback were not run for build 10. Prior v1.4.3 harness evidence is retained below.

The Liked Songs change holds Shuffle off until Spotify confirms the selected track, restores the previous Shuffle setting, and retries the selected URI alone if the URI list starts a different song. The regression harness and live Spotify playback were not verified for build 10.

## Superseded v1.4.4 — build 9 (replaced 2026-10-09)

Published on **2026-10-08**, Asia/Kolkata, as the first published v1.4.4 release (superseded by build 10). Annotated tag `v1.4.4` originally pointed to clean release commit `c40c3632d9bae2223c899e2ac2e46dee07966cd5`. GitHub Actions was not used.

- Both arm64 and x86_64 packages were built from the clean tagged source. Bundle version/build, architecture, plist, ad-hoc signature, archive contents, extracted executable equality, and checksums passed. Intel is cross-compiled; physical Intel runtime is unverified.
- All five uploaded assets (both ZIPs, `SHA256SUMS.txt`, `BUILD_INFO.txt`, and `RELEASE_NOTES.md`) were downloaded from GitHub and matched byte-for-byte with the local release snapshot.
- The regression harness was not run for the 1.4.4 changes. Dynamic OAuth still needs a live Spotify Dashboard authorization check after registering `http://127.0.0.1/callback` without a port. Real liked-song playback, clean installation, and physical Intel runtime remain unverified. Packages are ad-hoc signed and not notarized.

| Published ZIP | Bytes | SHA-256 |
| --- | ---: | --- |
| `SpotMenu-1.4.4-macos-arm64.zip` | 2708847 | `da76ebd5e6ddd90ba302ade46c98c23e36392a430d5cd18d6e9c60aa65316060` |
| `SpotMenu-1.4.4-macos-x86_64.zip` | 2756809 | `c48a2f61b34d2c74957bb2bbcefc5142f02fce5638c7caffac14e10599482eaf` |

## Published v1.4.3 — build 8

Published on **2026-10-01**, Asia/Calcutta, as a published GitHub release (the latest is [v1.4.4](https://github.com/heyaaakash/playmenu/releases/tag/v1.4.4)). The final repository check reports public visibility (the pre-release check reported private). Annotated tag `v1.4.3` points to clean release commit `f6663fe1739062588a73ddd1ab0cdeedee6c03c5`; the tag was pushed before uploading assets.

- The tagged source was rebuilt locally with `./Scripts/prepare-release.sh`: **46 passed, 0 failures, 0 skipped**. Screenshots stayed unchanged, and provenance records `source_state=clean`, version 1.4.3, build 8, and the exact tagged commit.
- Five assets were uploaded: arm64/x86_64 ZIPs, `SHA256SUMS.txt`, `BUILD_INFO.txt`, and `RELEASE_NOTES.md`. All were downloaded from the draft and compared byte-for-byte with local release assets before publication. Checksums, extracted signatures/plists, version/build, architecture, and bundled license passed for both downloaded ZIPs.
- Publication was explicit via GitHub CLI after verification. GitHub reports a published non-draft, non-prerelease with all five assets uploaded. GitHub Actions remains disabled; no hosted workflow was used.

| Published ZIP | Bytes | SHA-256 |
| --- | ---: | --- |
| `SpotMenu-1.4.3-macos-arm64.zip` | 2703717 | `cf9b794623cfc546d2cf1f3b633365294e2cf5bfa9f1022b72a4fb3cffe8552f` |
| `SpotMenu-1.4.3-macos-x86_64.zip` | 2751433 | `4857763d09f7bc1b1e9c3606e03a37c5d0ae77a9145812e3832014002e721d9b` |

This verifies build/upload integrity, not a clean installation or live Spotify journey. The packages remain ad-hoc signed and not notarized; Intel is cross-compiled without physical Intel runtime validation. The detailed automated/live limits below remain applicable.

## 1.4.3 automatic playback detection — build 8

Date: **2026-10-01**, Asia/Kolkata. Verified locally on Apple Silicon, macOS 27.0.1, Swift 6.4, macOS 26.5 SDK. GitHub Actions remains disabled.

- `./Scripts/prepare-release.sh`: **46 checks passed, 0 failures, 0 skipped**. Ten new regressions cover prompt synthetic desktop event updates, invalid payload bounds, remote/command guards, stale and 204 responses, slow saved-status lookup isolation, closed-menu detection, coalesced in-flight hints, menu wake and monitor stop/restart, automatic network recovery, Retry-After, and disconnect cancellation. Synthetic local state update is checked below 100 ms; that is not real Spotify notification latency.
- The full existing audio, state, appearance, geometry, API, and native render harness also passed. Test sessions have unique fixture tokens to keep late cancelled mock callbacks separate. All monitors in tests disable system observation; no real Spotify broadcast, account, audio capture, or permission is exercised.
- Nine screenshots were regenerated and are byte-identical to the previously reviewed 1.4.2 previews; no visual layout change is claimed.
- Both local ZIPs passed architecture/version/build checks, extraction, strict ad-hoc signature and plist checks, executable/license equality, package file allowlist, and SHA-256. x86_64 is cross-compiled and has no new Intel runtime evidence.
- Local review assets are in `dist/release-1.4.3/`, with working-tree provenance based on `b4cb43ad2e34f8ee07f69fe3deee07d56ac934d9`. Rebuild from the final clean tagged commit before drafting a release. No tag, release, or Actions run was created.

| Local package | Bytes | SHA-256 |
| --- | ---: | --- |
| `SpotMenu-1.4.3-macos-arm64.zip` | 2703717 | `30d782b082786cdf32df08097b2284d61dcf5e5d57c186c617d0dfdceff8e972` |
| `SpotMenu-1.4.3-macos-x86_64.zip` | 2751433 | `3cd08fa8b74432da1d03a15977bf6f346fd53726f3ee14dcd50bac9c79421ac0` |

Manual validation remains open for the installed Spotify version’s actual broadcasts, real detection/reconciliation latency, wake and network restoration, phone/browser playback, actual audio permission/capture, clean installation, and physical Intel use. The app remains ad-hoc signed and not notarized.

## 1.4.2 local release preparation — build 7

Verified on 2026-09-30 on Apple Silicon, macOS 27.0.1, Swift 6.4, using the installed macOS 26.5 SDK. GitHub Actions was disabled before the push; both workflow files were removed. Previous hosted results below are historical only.

- `./Scripts/prepare-release.sh` completed locally: **36 checks passed, 0 failures, 0 skipped**, nine native fictional-data screenshots regenerated and visually reviewed, both architecture packages built, and staged release checksums verified.
- arm64 was built for the host; x86_64 was cross-compiled with a macOS 14 deployment triple. Each ZIP was extracted and checked for matching architecture/version/build, valid ad-hoc signature, valid plist, identical executable, matching MIT license, an allowed file list, and SHA-256.
- The normal local `verify.sh` entry point runs tests and package verification. Its argument validation and refusal to skip native rendering were checked, along with invalid architecture rejection, release-preparation skip rejection, and draft upload rejection for an uncommitted tree.
- `dist/release-1.4.2/` contains both ZIPs, aggregate checksums, copied release notes, and build provenance. This preparation used a working tree based on `1c40823359ee3a69787e83b85ebb67ad579dbfd3`; provenance correctly records `source_state=dirty`. Rebuild from the final clean tagged commit before uploading a draft. No tag or release was created.

| Local package | Bytes | SHA-256 |
| --- | ---: | --- |
| `SpotMenu-1.4.2-macos-arm64.zip` | 2676990 | `e307f8b89b694aafaddb4918c85991baf2814fa2ec5bc027457f50af693b225d` |
| `SpotMenu-1.4.2-macos-x86_64.zip` | 2724040 | `ad61bbc39d809ff3d338f1dcd11819a815b7daa2c3e3c977cd3bcb5bfa8b2006` |

These are local review packages. Physical Intel runtime, live Spotify capture/permissions, minimum macOS installation, clean installation, and notarization remain unverified. Build success and synthetic/native fixtures establish only their specific checks.

## Earlier 1.4.2 working-source package — build 7

Date: **2026-09-30**, Asia/Kolkata. Same Apple Silicon/macOS/toolchain environment as the records below.

- `./Scripts/test.sh`: **36 passed, 0 failures, 0 skipped**. New assertions verify continuity when audio targets alternate rapidly, small per-frame wave changes across the clock-hour boundary, invalid target handling, and stopped-motion flattening.
- Native live/paused waveform fixtures rendered in both themes. The dark waveform layout was visually reviewed with fictional data and injected synthetic audio. These checks do not establish perceived smoothness during real Spotify playback or audio capture.
- `./Scripts/package.sh` rebuilt the Apple Silicon app/ZIP; version/build, plist, ad-hoc signature, SHA-256, archive allowlist, and round-trip executable equality passed. `git diff --check` passed.

| ZIP | Bytes | SHA-256 |
| --- | --- | --- |
| `SpotMenu-1.4.2-macos-arm64.zip` | 2676990 | `bcb31eb04db581f4a5b169bf8c61c74bbaa7e73237f730435cea59ea42695bfe` |

Working-source package only, without new CI, Intel build, published tag, clean installation, or live capture/permission validation. Capture remains capped at 30 frames per second; the small visible waveform draws at up to 60, with no real-capture CPU measurement claimed.

## 1.4.1 local working source — build 6

Date: **2026-09-30**, Asia/Kolkata. Same Apple Silicon/macOS/toolchain environment as the 1.4.0 record below.

- `./Scripts/test.sh`: **36 passed, 0 failures, 0 skipped**, including bounded measured/decorative waveform layers, stopped-motion flattening, existing seek controls, and fixed compact/expanded dimensions.
- Native fixtures rendered eight screens in both appearances, with synthetic live waveform and paused waveform states. Light/dark waveform layouts and the simplified Settings view were visually reviewed. Fictional songs/artwork and mock capture only; no actual audio tap or real Spotify account.
- The seek thumb now loads the current position immediately on menu presentation and track changes; preview position matched the elapsed-time label.
- `./Scripts/package.sh` rebuilt the Apple Silicon app/ZIP. Version/build, plist, ad-hoc signature, SHA-256, allowed bundle contents, and round-trip executable equality passed. `git diff --check` passed.

| ZIP | Bytes | SHA-256 |
| --- | --- | --- |
| `SpotMenu-1.4.1-macos-arm64.zip` | 2674833 | `67ea8f09e30ba7489fd6beec01ccd98a49d3ae667218f1bc5718fd105857eb07` |

Local working-source package only: no new CI, Intel build, published tag, clean installation, or live Spotify capture/permission validation. The app remains ad-hoc signed and not notarized.

## 1.4.0 local working source — build 5

Date: **2026-09-30**, Asia/Kolkata. These checks used the current working tree on Apple Silicon (`arm64`), macOS 27.0.1, Swift 6.4, and the installed macOS 26.5 SDK fallback.

| Check | Result and scope |
| --- | --- |
| Regression harness | `./Scripts/test.sh`: **36 passed, 0 failures, 0 skipped**. Synthetic PCM, mock capture/HTTP, isolated preferences/caches, and fixture token; no real Spotify requests, account, Keychain, or audio tap. |
| Capture recovery | Mocked cancellation, hidden/remote suspension, stale callback rejection, retained Settings errors, successful recovery, and opt-in persistence passed. |
| Native UI fixtures | Eight screens in both appearances: Compact, Home, Library, Search, Devices, Settings, live Spectrum, and live Waveform. Spectrum/waveform previews use synthetic measurements and fictional data. Both visualization layouts were visually reviewed. |
| Release package | `./Scripts/package.sh` rebuilt `dist/SpotMenu.app` and the Apple Silicon ZIP. Plist version/build/usage description, ad-hoc signature, SHA-256, archive file allowlist, and round-trip executable equality passed. |
| Source hygiene | `git diff --check` passed. |

| ZIP | Bytes | SHA-256 |
| --- | --- | --- |
| `SpotMenu-1.4.0-macos-arm64.zip` | 2691792 | `b454a75496197083714b4ef3396eff748786a108205e09daad8ff0e40f537697` |

This is a local working-source artifact, without a published tag, new CI run, or Intel 1.4.0 build. Live Spotify capture, audio permission allow/deny/retry, actual output devices, perceived beat alignment, and CPU measurements during real capture remain unverified. The new visualizer does not establish a BPM or musical beat grid. The package is ad-hoc signed and not notarized.

## 1.3.0 historical validation

Version: **1.3.0**, build **4**. Date: **2026-09-30**, Asia/Kolkata.

### Historical local checks

| Check | Result and scope |
| --- | --- |
| Environment | Apple Silicon (`arm64`), macOS 27.0.1, Apple Swift 6.4, installed macOS 26.5 SDK selected by the documented fallback |
| Source build | Fresh isolated clone of the extracted project, with this repository-preparation change applied; optimized release build passed |
| Regression harness | `./Scripts/test.sh`: **30 passed, 0 failures**; mock HTTP, isolated defaults/caches, fixture token |
| Native UI previews | `./Scripts/screenshots.sh`: nine Retina PNGs; actual SwiftUI/AppKit views, fictional data, locally drawn sample artwork |
| Package | `./Scripts/package.sh`: Apple Silicon ZIP produced; plist/version/build number, ad-hoc signature, SHA-256, extracted executable equality, and package file allowlist passed |
| Bundle contents | Executable, app icon, MIT license, plist, and signature metadata only |
| Repository checks | Shell syntax, YAML parsing, pinned action refs, whitespace, and relative documentation/image paths checked |

The local package is a working-source review artifact in `dist/`; it is not attached to a published release or tied to an immutable release tag. These historical packages were also built from committed source by the former hosted workflow.

### Historical CI — retired

The [Verify workflow](https://github.com/heyaaakash/playmenu/actions/runs/36713797814) **passed both jobs** on macOS 15.7.9, Swift 6.1.2, from source commit `cbc9350fd15e98b278020b87a9df26002c248912`.

| Runner | Result |
| --- | --- |
| Apple Silicon (`macos-15`) | 30 checks passed, 0 failures, 0 skipped; app/ZIP packaging and upload passed |
| Intel (`macos-15-intel`) | 29 checks passed, 0 failures, 1 explicitly skipped native-render fixture; app/ZIP packaging and upload passed |

The [initial run](https://github.com/heyaaakash/playmenu/actions/runs/36713483979) exposed a Metal assertion in the Intel VM during native snapshot rendering. That run reported one skipped check for the Intel hosted runner; the check executes in current local verification. This does not establish native rendering on physical Intel hardware. CI never uses a Spotify account or exercises live playback/permissions.

Both uploaded CI ZIPs were downloaded on 2026-09-30 and checked independently: SHA-256 matched, signatures and plists verified, bundle version was 1.3.0, architecture matched the filename, and the bundled license matched the repository license. They are local review artifacts in `dist/`, not a public release. GitHub CI artifacts have a 14-day retention policy.

| ZIP | Bytes | SHA-256 |
| --- | --- | --- |
| `SpotMenu-1.3.0-macos-arm64.zip` | 2609132 | `77033c3e7d27c2e71cb5134cd8d226cd7ebd1fa91287d91a1cc9c83bb3aed5be` |
| `SpotMenu-1.3.0-macos-x86_64.zip` | 2629951 | `b9a2892b8e37228c155c53660230f46639d543ceeb898f1555e5b64aeeaf57b8` |

## Remaining manual validation

Live browser authorization, real Spotify playback/library mutation, active-device transfers, actual allow/deny Automation prompts, clean downloaded-app installation, upgrade/downgrade, uninstall verification, physical Intel use, minimum macOS 14 use, VoiceOver, and complete keyboard-only use remain open. No Developer ID, notarization, auto-update, public download, or third-party user validation is claimed.

CI status, screenshots, and a local release build are evidence for their specific checks only. See [the capability matrix](CAPABILITY_MATRIX.md) before making broader support claims.

## Output layout migration — 2026-10-01

Local app outputs now use `dist/<version>/apps/<architecture>/`, `packages/`, and `release/`. Promotional media is separate in `dist/media/`; other non-release deliverables belong in `dist/other/`. Historical paths above describe the layout used at the time of validation: `dist/release-X/` is now `dist/X/release/`, flat ZIPs/checksums are now `dist/X/packages/`, and the app is under its bundled version and architecture. Existing package/release bytes were preserved; GitHub release assets and tags were not changed. See [development output layout](DEVELOPMENT.md#generated-output-layout).

Validation of the updated scripts used `SPOTMENU_DIST_ROOT=/private/tmp/spotmenu-dist-layout-check ./Scripts/prepare-release.sh` from the working tree based on `29b59ed`. All 46 checks passed with zero failures/skips; nine screenshots rendered without tracked image changes. Both architectures were built into separate app directories, packaged, extracted, and checked for plist metadata, architecture, license, signature, archive allowlist, and SHA-256. The five-file release snapshot passed its aggregate manifest. Provenance correctly reports dirty source; these are local layout checks, not a newly tagged or published release.

The migration compared all 155 moved files byte-for-byte before navigational README updates. Existing package, release, and media manifests passed all 22 checksum entries. A temporary clean Git fixture with a stub GitHub CLI verified that draft upload selects exactly the five files from the versioned `release/` directory, and that dirty/stale provenance is rejected; it made no GitHub requests. Shared paths were also checked with a spaced alternate root and invalid architecture. This does not add live Spotify or target-hardware runtime validation.

Promotional-output separation: both launch projects were moved to `dist/media/`, with all 124 files compared byte-for-byte before updating their navigational READMEs. Version folders were checked to contain only `apps/`, `packages/`, and `release/`. Shared-path checks with versions 1.4.3 and 2.0.0 confirmed that `media/` and `other/` remain independent of the version, including a spaced alternate output root. Shell syntax and all 22 existing package/release/media checksum entries passed. App build paths were unchanged, so the previous full build results apply; this correction did not rebuild or publish artifacts.
