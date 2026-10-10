#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source ./Scripts/dist-paths.sh
[[ $# == 0 ]] || { echo "Usage: $0" >&2; exit 1; }
command -v gh >/dev/null || { echo "Install and authenticate GitHub CLI first." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit changes, then run prepare-release.sh from the clean tree." >&2; exit 1; }
tag="v${version}"
commit="$(git rev-parse HEAD)"
repo=heyaaakash/playmenu
[[ "$(git rev-parse "refs/tags/${tag}^{commit}")" == "$commit" ]] || { echo "The existing $tag must point to HEAD." >&2; exit 1; }
[[ "$(gh api "repos/${repo}/commits/${tag}" --jq .sha)" == "$commit" ]] || { echo "Push the existing tag before drafting." >&2; exit 1; }
[[ -f "$release_dir/BUILD_INFO.txt" ]] || { echo "Run ./Scripts/prepare-release.sh first." >&2; exit 1; }
# Require provenance from this clean commit; never upload dirty or stale packages.
for line in "version=$version" "build=$(<BUILD_NUMBER)" "source_commit=$commit" "source_state=clean"; do
  rg -F -x -- "$line" "$release_dir/BUILD_INFO.txt" >/dev/null || { echo "Release provenance mismatch; rerun prepare-release.sh." >&2; exit 1; }
done
cmp Docs/RELEASE_NOTES.md "$release_dir/RELEASE_NOTES.md"
(cd "$release_dir"; shasum -a 256 -c SHA256SUMS.txt)
for architecture in arm64 x86_64; do
  [[ -f "$release_dir/PlayMenu-${version}-macos-${architecture}.zip" ]]
done
gh release create "$tag" \
  "$release_dir/PlayMenu-${version}-macos-arm64.zip" \
  "$release_dir/PlayMenu-${version}-macos-x86_64.zip" \
  "$release_dir/SHA256SUMS.txt" "$release_dir/BUILD_INFO.txt" "$release_dir/RELEASE_NOTES.md" \
  --repo "$repo" --draft --verify-tag --title "PlayMenu $tag" \
  --notes-file "$release_dir/RELEASE_NOTES.md"
