#!/bin/zsh
#
# Builds dist/Glint.app (Release).
#
#   ./scripts/build-app.sh             universal (arm64 + x86_64), ad-hoc signed — what releases ship
#   ./scripts/build-app.sh --native    only this Mac's architecture (faster while iterating)
#   ./scripts/build-app.sh --dev-sign  sign with the Apple Development identity in project.yml instead of ad-hoc
#                                      (keeps the same signature across builds, so Accessibility stays granted)
#   ./scripts/build-app.sh --install   also copy to /Applications and relaunch
#
set -euo pipefail
root="${0:A:h:h}"
cd "$root"

archs="arm64 x86_64"
install=0
dev_sign=0
for arg in "$@"; do
    case "$arg" in
        --native) archs="$(uname -m)" ;;
        --install) install=1 ;;
        --dev-sign) dev_sign=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }
xcodegen generate -q

signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= OTHER_CODE_SIGN_FLAGS=--timestamp=none)
(( dev_sign )) && signing=()

xcodebuild -project Glint.xcodeproj -scheme Glint -configuration Release -derivedDataPath build/Release \
    -destination 'generic/platform=macOS' ARCHS="$archs" ONLY_ACTIVE_ARCH=NO "${signing[@]}" build -quiet \
    2>&1 | grep -v "Using the first of multiple matching destinations" || true

app="build/Release/Build/Products/Release/Glint.app"
[[ -d "$app" ]] || { echo "Build failed" >&2; exit 1; }
rm -rf dist/Glint.app && mkdir -p dist
ditto "$app" dist/Glint.app
echo "Built dist/Glint.app ($(lipo -archs dist/Glint.app/Contents/MacOS/Glint))"

if (( install )); then
    pkill -x Glint 2>/dev/null || true
    rm -rf /Applications/Glint.app
    ditto dist/Glint.app /Applications/Glint.app
    open /Applications/Glint.app
    echo "Installed to /Applications and launched"
fi
