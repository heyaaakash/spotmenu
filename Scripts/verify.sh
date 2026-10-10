#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
[[ $# == 0 || ( $# == 1 && "$1" == --screenshots ) ]] || { echo "Usage: $0 [--screenshots]" >&2; exit 1; }
[[ "${PLAYMENU_SKIP_UI_RENDER:-${SPOTMENU_SKIP_UI_RENDER:-0}}" != 1 ]] || { echo "Verification requires native rendering; unset PLAYMENU_SKIP_UI_RENDER." >&2; exit 1; }
./Scripts/test.sh
./Scripts/package.sh
if [[ "${1:-}" == --screenshots ]]; then ./Scripts/screenshots.sh; fi
echo "Local regression and package checks passed."
