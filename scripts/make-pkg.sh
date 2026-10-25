#!/bin/bash
set -euo pipefail

# Packs the built app into a double-click installer that puts it in /Applications and opens it.
cd "$(dirname "$0")/.."
app=".build/package/Bubblecast.app"
[ -d "$app" ] || { echo "Missing $app. Run scripts/build-app.sh first." >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rm -rf dist
mkdir -p "$work/root" dist
cp -R "$app" "$work/root/"
pkgbuild --analyze --root "$work/root" "$work/components.plist" >/dev/null
# Without this, Installer "upgrades" any other copy it finds instead of installing into /Applications.
plutil -replace 0.BundleIsRelocatable -bool NO "$work/components.plist"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
pkgbuild --root "$work/root" --component-plist "$work/components.plist" --scripts scripts/installer \
    --identifier io.github.mehedisarkar2k.bubblecast.pkg --version "$version" \
    --install-location /Applications "dist/Bubblecast-$version.pkg"
echo "Built dist/Bubblecast-$version.pkg"
