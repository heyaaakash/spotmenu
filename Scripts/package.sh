#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source ./Scripts/dist-paths.sh
export PLAYMENU_REGISTER_APP=0
./Scripts/build-app.sh
architecture="$(lipo -archs "${app}/Contents/MacOS/PlayMenu")"
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { echo "Expected one architecture, got: $architecture" >&2; exit 1; }
name="PlayMenu-${version}-macos-${architecture}.zip"
mkdir -p "$packages_dir"
archive="${packages_dir}/${name}"
ditto -c -k --keepParent --norsrc "$app" "$archive"
check_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/playmenu-package.XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT
ditto -x -k "$archive" "$check_dir"
codesign --verify --strict --verbose=2 "${check_dir}/PlayMenu.app"
plutil -lint "${check_dir}/PlayMenu.app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${check_dir}/PlayMenu.app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${check_dir}/PlayMenu.app/Contents/Info.plist")" == "$(<BUILD_NUMBER)" ]]
cmp "$app/Contents/MacOS/PlayMenu" "${check_dir}/PlayMenu.app/Contents/MacOS/PlayMenu"
cmp LICENSE "${check_dir}/PlayMenu.app/Contents/Resources/LICENSE.txt"
[[ "$(lipo -archs "${check_dir}/PlayMenu.app/Contents/MacOS/PlayMenu")" == "$architecture" ]]
# A distribution ZIP contains only the app executable, icon, license, plist, and signature.
expected="Contents/Info.plist Contents/MacOS/PlayMenu Contents/Resources/PlayMenu.icns Contents/Resources/LICENSE.txt Contents/_CodeSignature/CodeResources"
for file in "${check_dir}/PlayMenu.app"/**/*(.DN); do
  relative="${file#${check_dir}/PlayMenu.app/}"
  [[ " $expected " == *" $relative "* ]] || { echo "Unexpected package file: $relative" >&2; exit 1; }
done
(cd "$packages_dir"; shasum -a 256 "$name" > "${name}.sha256"; shasum -a 256 -c "${name}.sha256")
echo "Packaged ${archive} (ad-hoc signed; not notarized)"
