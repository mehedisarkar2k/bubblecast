#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app=".build/package/Bubblecast.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/Bubblecast" "$app/Contents/MacOS/Bubblecast"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# macOS keeps camera, microphone and screen permissions only while the signing identity stays the same,
# so sign with a real certificate when one exists; ad-hoc signing makes every build look like a new app.
identity="${BUBBLECAST_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identities="$(security find-identity -p codesigning 2>/dev/null | grep -vE "EXPIRED|REVOKED" || true)"
    for name in "Developer ID Application" "Apple Development" "Bubblecast Dev"; do
        identity="$(printf '%s\n' "$identities" | grep -F "\"$name" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
        [ -n "$identity" ] && break
    done
fi
if [ -n "$identity" ]; then
    codesign --force --deep -s "$identity" "$app"
    echo "Signed with: $identity"
else
    # An ad-hoc signature's default requirement is the exact code hash, so macOS would treat every build
    # as a new app; requiring only the bundle identifier lets granted permissions carry over.
    codesign --force --deep -s - -r '=designated => identifier "io.github.mehedisarkar2k.bubblecast"' "$app"
    echo "No signing certificate found, signed ad-hoc with a bundle-identifier requirement."
fi
echo "Built $app"
