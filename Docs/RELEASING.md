# Releasing SpotMenu

All verification, screenshots, packaging, and release preparation run on a Mac. GitHub Actions is disabled and workflow files have been removed. Packages are ad-hoc signed and not notarized; automatic updates and Developer ID distribution are not configured.

## Prepare locally

1. Update `VERSION`, `BUILD_NUMBER`, `CHANGELOG.md`, and `Docs/RELEASE_NOTES.md`. Current source: 1.4.4, build 10.
2. Run `./Scripts/prepare-release.sh`. It runs every native regression check, refreshes fictional-data screenshots, builds arm64 and x86_64 ZIPs sequentially, round-trip verifies each app, and stages both ZIPs, `SHA256SUMS.txt`, release notes, and `BUILD_INFO.txt` in `dist/<version>/release/`. App bundles are retained separately in `dist/<version>/apps/arm64/SpotMenu.app` and `dist/<version>/apps/x86_64/SpotMenu.app`; the working ZIPs and individual checksum files are in `dist/<version>/packages/`.
3. Review screenshots and update [VALIDATION.md](VALIDATION.md) and [CAPABILITY_MATRIX.md](CAPABILITY_MATRIX.md). Cross-compilation verifies the Intel package, not Intel runtime behavior. Perform live sign-in/playback, permission handling, clean installation, upgrade/uninstall, and physical-device testing for the environments you will claim.
4. Commit the final source, screenshots, and evidence; push it. Generated `dist/` files stay outside Git. Rerun release preparation from that clean commit so its provenance says `source_state=clean` and identifies the exact commit.

For ordinary changes, use `./Scripts/verify.sh` before pushing; add `--screenshots` for UI changes. No GitHub credentials are needed to verify or prepare packages locally. The scripts honor `SDKROOT`; all checks run on the host architecture with native rendering enabled.

## Upload a draft

After reviewing the exact commit, create and push an immutable version tag matching `VERSION`, for example:

```sh
git tag -a "v$(cat VERSION)" -m "SpotMenu $(cat VERSION)"
git push origin "v$(cat VERSION)"
./Scripts/draft-release.sh
```

The upload script needs authenticated GitHub CLI and `rg`. It checks the clean tree, local and remote tag commits, version/build provenance, staged notes, and checksums. It uploads both ZIPs, checksums, and build information using `gh release create --draft --verify-tag`. It never creates/moves a tag or publishes a public release. An existing release is not overwritten.

The upload script reads only `dist/<version>/release/`; app bundles, working packages, and media are not uploaded. Version folders contain only app builds, packages, and release snapshots; promotional media lives separately in `dist/media/<project>/`, and other non-release deliverables in `dist/other/<task>/`. This flat directory is a verified release snapshot with checksum paths relative to that directory. Release filenames and GitHub URLs are unchanged by the local folder layout. See [generated output layout](DEVELOPMENT.md#generated-output-layout).

Download every draft asset, check the hashes, and install/open the actual downloads on the target Macs. Update release claims from those results. Final publication remains an explicit owner action in GitHub Releases; verify the published page and support links afterward. Binary releases are available on the [Releases page](https://github.com/heyaaakash/spotify-mac-menu/releases).

## Credentials and signing

Tests and previews use mocked requests and fictional data. They never need Spotify account credentials. Keep GitHub authentication, signing certificates, private keys, and notary credentials outside Git. Upload authorization comes from the local GitHub CLI session.

For Developer ID distribution, configure hardened runtime, entitlements, secure timestamps, notarization, and stapling using [Apple’s documentation](https://developer.apple.com/developer-id/). Test the downloaded result on a separate Mac before changing trust claims.

## Rollback and maintenance

Keep the previous verified ZIP/checksum when a release exists. For a bad release, explain the issue, stop recommending that version, and publish a new immutable version from the corrected commit. Do not silently replace published tags or assume older binaries can read newer local data.

The owner/maintainer is `heyaaakash`. Triage reported bugs and local check failures, review dependencies monthly, and recheck Spotify restrictions before releases. Refresh validation records and screenshots when behavior changes. Private security reports follow [SECURITY.md](../SECURITY.md).
