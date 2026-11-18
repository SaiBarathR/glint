#!/bin/zsh
# Builds Glint.app (Release) into dist/ and zips it.
#   scripts/build.sh            build + zip
#   scripts/build.sh --install  also copy to /Applications and relaunch
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate -q
xcodebuild -project Glint.xcodeproj -scheme Glint -configuration Release -derivedDataPath build/Release \
  -destination 'platform=macOS' build -quiet 2>&1 | grep -v "Using the first of multiple matching destinations" || true
test -d build/Release/Build/Products/Release/Glint.app || { echo "Build failed"; exit 1; }
rm -rf dist && mkdir -p dist
cp -R build/Release/Build/Products/Release/Glint.app dist/
ditto -c -k --keepParent dist/Glint.app dist/Glint.zip
echo "Built dist/Glint.app and dist/Glint.zip"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Glint 2>/dev/null || true
  rm -rf /Applications/Glint.app
  cp -R dist/Glint.app /Applications/
  open /Applications/Glint.app
  echo "Installed to /Applications and launched"
fi
