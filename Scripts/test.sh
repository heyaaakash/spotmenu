#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
  export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/playmenu-clang-cache"
mkdir -p .build
swiftc -swift-version 6 -parse-as-library -D PLAYMENU_CHECKS -sdk "$SDKROOT" -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/PlayMenu/*.swift Tests/PlayMenuTests/PlayMenuTests.swift -o .build/PlayMenuChecks
.build/PlayMenuChecks
