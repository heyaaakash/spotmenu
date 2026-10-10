#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/playmenu-clang-cache"

source ./Scripts/dist-paths.sh
build_number="$(<BUILD_NUMBER)"
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "Invalid BUILD_NUMBER" >&2; exit 1; }

build_args=(--disable-sandbox --scratch-path ".build/release-${architecture}" -c release --triple "${architecture}-apple-macosx14.0")
./Scripts/build-icon.sh
swift build "${build_args[@]}" -debug-info-format none
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
[[ "$(lipo -archs "${binary_dir}/PlayMenu")" == "$architecture" ]] || { echo "Built architecture does not match $architecture" >&2; exit 1; }
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/playmenu-bundle.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
bundle="${stage}/PlayMenu.app"
mkdir -p "${bundle}/Contents/MacOS" "${bundle}/Contents/Resources"
cp "${binary_dir}/PlayMenu" "${bundle}/Contents/MacOS/PlayMenu"
cp Resources/PlayMenu.icns "${bundle}/Contents/Resources/PlayMenu.icns"
cp LICENSE "${bundle}/Contents/Resources/LICENSE.txt"
cat > "${bundle}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PlayMenu</string>
  <key>CFBundleDisplayName</key><string>PlayMenu</string>
  <key>CFBundleIdentifier</key><string>com.spotmenu.app</string>
  <key>CFBundleExecutable</key><string>PlayMenu</string>
  <key>CFBundleIconFile</key><string>PlayMenu.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${build_number}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>PlayMenu analyzes Spotify audio on this Mac to animate its waveform and detect musical pulses. Audio stays in memory and is never recorded or uploaded.</string>
  <key>NSAppleEventsUsageDescription</key><string>PlayMenu controls playback in Spotify when Spotify's Web API cannot reach the active device.</string>
</dict></plist>
PLIST
plutil -lint "${bundle}/Contents/Info.plist"
codesign --force --sign - "${bundle}"
codesign --verify --strict --verbose=2 "${bundle}"
mkdir -p "$app_dir"
rm -rf -- "${app}"
mv "${bundle}" "${app}"
# Finder can keep a cached icon when only files inside an existing app change.
touch "${app}"
registrar="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ "${PLAYMENU_REGISTER_APP:-${SPOTMENU_REGISTER_APP:-1}}" == 1 && -x "${registrar}" ]]; then
  "${registrar}" -f "${app}" || echo "Finder registration unavailable; the app bundle was built successfully." >&2
fi
echo "Built ${app}"
