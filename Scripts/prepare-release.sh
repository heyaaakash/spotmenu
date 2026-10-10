#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source ./Scripts/dist-paths.sh
[[ $# == 0 ]] || { echo "Usage: $0" >&2; exit 1; }
[[ "${PLAYMENU_SKIP_UI_RENDER:-${SPOTMENU_SKIP_UI_RENDER:-0}}" != 1 ]] || { echo "Release preparation requires all checks; unset PLAYMENU_SKIP_UI_RENDER." >&2; exit 1; }
./Scripts/test.sh
./Scripts/screenshots.sh
# Build each target separately; both architecture app bundles are retained.
host_arch="$(uname -m)"
[[ "$host_arch" == arm64 || "$host_arch" == x86_64 ]] || { echo "Unsupported host architecture" >&2; exit 1; }
other_arch=x86_64
[[ "$host_arch" != x86_64 ]] || other_arch=arm64
for architecture in "$other_arch" "$host_arch"; do
  PLAYMENU_ARCH="$architecture" ./Scripts/package.sh
done
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/playmenu-release.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
for architecture in arm64 x86_64; do
  cp "$packages_dir/PlayMenu-${version}-macos-${architecture}.zip" "$stage/"
done
cp Docs/RELEASE_NOTES.md "$stage/RELEASE_NOTES.md"
source_state=clean
[[ -z "$(git status --porcelain)" ]] || source_state=dirty
{
  echo "version=$version"
  echo "build=$(<BUILD_NUMBER)"
  echo "source_commit=$(git rev-parse HEAD)"
  echo "source_state=$source_state"
  echo "built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host_arch=$host_arch"
  echo "macos=$(sw_vers -productVersion)"
  swift --version
  echo "Signing: ad-hoc, not notarized. Other architecture cross-compiled; runtime unverified."
} > "$stage/BUILD_INFO.txt"
(cd "$stage"; shasum -a 256 PlayMenu-*.zip RELEASE_NOTES.md BUILD_INFO.txt > SHA256SUMS.txt; shasum -a 256 -c SHA256SUMS.txt)
mkdir -p "$version_dir"
rm -rf -- "$release_dir"
mv "$stage" "$release_dir"
echo "Prepared $release_dir ($source_state source). No tag or GitHub release created."
