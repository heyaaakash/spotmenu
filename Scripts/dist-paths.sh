#!/bin/zsh
# Source after changing to the repository root. Shared release and media paths.
version="$(<VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
architecture="${PLAYMENU_ARCH:-${SPOTMENU_ARCH:-$(uname -m)}}"
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { echo "Unsupported PLAYMENU_ARCH: $architecture" >&2; exit 1; }
# An alternate root allows isolated verification without replacing local releases.
playmenu_dist_root="${PLAYMENU_DIST_ROOT:-${SPOTMENU_DIST_ROOT:-${PWD}/dist}}"
playmenu_dist_root="${playmenu_dist_root:A}"
version_dir="${playmenu_dist_root}/${version}"
app_dir="${version_dir}/apps/${architecture}"
app="${app_dir}/PlayMenu.app"
packages_dir="${version_dir}/packages"
release_dir="${version_dir}/release"
# Promotional and other non-release outputs are independent of app versions.
media_dir="${playmenu_dist_root}/media"
other_dir="${playmenu_dist_root}/other"
